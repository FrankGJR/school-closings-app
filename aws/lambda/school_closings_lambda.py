import json
import os
import re
import urllib.request
import boto3
from datetime import datetime
from zoneinfo import ZoneInfo

# AWS clients
s3_client = boto3.client('s3')
sns_client = boto3.client('sns')
dynamodb = boto3.resource('dynamodb')
BUCKET_NAME = 'cardinal-driving-school-closings'
JSON_FILE_KEY = 'school_closings.json'
STATE_TABLE = os.environ.get('STATE_TABLE', 'SchoolClosingsState')
STATE_PK = 'state'
SNS_TOPIC_ARN = os.environ.get('SNS_TOPIC_ARN', 'arn:aws:sns:us-east-1:058264293996:SchoolClosingsAlerts')
SITE_URL = 'https://frankgjr.github.io/school-closings-app/'

# Eastern timezone
EASTERN = ZoneInfo('America/New_York')

# School filter list
SCHOOL_FILTER = [
    'gengras',
    'oak hill',
    'solterra',
    'partnership',
    'edadvance',
    'aces',
    'aspire',
    'naugatuck public',
    'naugatuck schools',
    'southington public',
    'southington schools',
    'hope academy',
    'bridges of aces',
    'bristol public',
    'bristol schools',
    'winsted public',
    'winsted schools',
    'terryville',
    'terryville schools',
    'plymouth',
    'plymouth schools',
    'canton public',
    'canton schools'
]


def strip_html_tags(text):
    """Remove HTML tags from text"""
    try:
        clean = re.compile('<.*?>')
        return re.sub(clean, '', text).strip()
    except Exception as e:
        print(f"Error stripping HTML tags: {str(e)}")
        return text


def decode_html_entities(text):
    """Decode HTML entities"""
    try:
        entities = {
            '&amp;': '&',
            '&lt;': '<',
            '&gt;': '>',
            '&quot;': '"',
            '&#39;': "'",
            '&nbsp;': ' ',
        }
        for entity, char in entities.items():
            text = text.replace(entity, char)
        return text
    except Exception as e:
        print(f"Error decoding entities: {str(e)}")
        return text


def get_eastern_time():
    """Get current time in Eastern timezone"""
    return datetime.now(EASTERN)

def get_state_table():
    return dynamodb.Table(STATE_TABLE)

def load_state():
    """Load storm notification state from DynamoDB"""
    try:
        resp = get_state_table().get_item(Key={'id': STATE_PK})
        return resp.get('Item', {})
    except Exception as e:
        print(f"Error loading state: {str(e)}")
        return {}

def save_state(state):
    """Save storm notification state to DynamoDB"""
    try:
        state['id'] = STATE_PK
        get_state_table().put_item(Item=state)
        return True
    except Exception as e:
        print(f"Error saving state: {str(e)}")
        return False

def should_reset_notification(state, now_eastern, reset_hours=4):
    """Reset when there has been no data for reset_hours"""
    last_nonempty = state.get('last_nonempty_time')
    if not last_nonempty:
        return True

    try:
        last_time = datetime.fromisoformat(last_nonempty)
    except Exception:
        return True

    delta = now_eastern - last_time
    return delta.total_seconds() >= reset_hours * 3600

def send_notification(entries, last_updated):
    """Send a one-time SNS email notification"""
    if not SNS_TOPIC_ARN:
        print("SNS_TOPIC_ARN not configured; skipping notification.")
        return False

    count = len(entries)
    subject = "School Closings Alert"
    message = (
        f"School closings found: {count}\n"
        f"Last updated: {last_updated}\n"
        f"View the site: {SITE_URL}\n"
    )

    try:
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject,
            Message=message
        )
        return True
    except Exception as e:
        print(f"Error sending SNS notification: {str(e)}")
        return False


def get_closings_from_source(url, source_name):
    """Fetch and parse closings from a source"""
    entries = []

    try:
        print(f"Fetching {source_name} from {url}")
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})

        # Reduced timeout to avoid Lambda timeout
        with urllib.request.urlopen(req, timeout=8) as response:
            html_content = response.read().decode('utf-8')

        if source_name == "WFSB":
            # WFSB pattern
            pattern = r'<FONT\s+CLASS="orgname"[^>]*>(.*?)</FONT>[^:]*:\s*<FONT\s+CLASS="status"[^>]*>([^<]+)</FONT>'
            matches = re.finditer(pattern, html_content, re.IGNORECASE | re.DOTALL)

            for match in matches:
                try:
                    raw_name = match.group(1)
                    raw_status = match.group(2)

                    clean_name = strip_html_tags(decode_html_entities(raw_name)).strip()
                    clean_status = strip_html_tags(decode_html_entities(raw_status)).strip()

                    should_include = any(school.lower() in clean_name.lower() for school in SCHOOL_FILTER)

                    if should_include and clean_name and clean_status and '<' not in clean_name:
                        entries.append({
                            "Name": clean_name,
                            "Status": clean_status,
                            "UpdateTime": get_eastern_time().strftime("%m/%d/%Y %I:%M:%S %p") + " EST",
                            "Source": source_name
                        })
                except Exception as e:
                    print(f"Error processing WFSB entry: {str(e)}")
                    continue

        else:  # NBC Connecticut
            # NBC pattern
            pattern = r'<h4[^>]*>(.*?)</h4>\s*<p[^>]*>(.*?)</p>'
            matches = re.finditer(pattern, html_content, re.IGNORECASE | re.DOTALL)

            for match in matches:
                try:
                    raw_name = match.group(1)
                    raw_status = match.group(2)

                    clean_name = strip_html_tags(decode_html_entities(raw_name)).strip()
                    clean_status = strip_html_tags(decode_html_entities(raw_status)).strip()

                    should_include = any(school.lower() in clean_name.lower() for school in SCHOOL_FILTER)

                    if should_include and clean_name and clean_status and '<' not in clean_name:
                        entries.append({
                            "Name": clean_name,
                            "Status": clean_status,
                            "UpdateTime": get_eastern_time().strftime("%m/%d/%Y %I:%M:%S %p") + " EST",
                            "Source": source_name
                        })
                except Exception as e:
                    print(f"Error processing NBC entry: {str(e)}")
                    continue

        print(f"Found {len(entries)} entries from {source_name}")

    except urllib.error.URLError as e:
        print(f"Network error fetching {source_name}: {str(e)}")
    except Exception as e:
        print(f"Unexpected error fetching {source_name}: {str(e)}")

    return entries


def upload_to_s3(data):
    """Upload JSON data to S3 - non-critical, won't fail Lambda if this fails"""
    try:
        json_string = json.dumps(data, indent=2)
        s3_client.put_object(
            Bucket=BUCKET_NAME,
            Key=JSON_FILE_KEY,
            Body=json_string,
            ContentType='application/json'
        )
        print(f"Successfully uploaded to S3: {BUCKET_NAME}/{JSON_FILE_KEY}")
        return True
    except Exception as e:
        print(f"S3 upload failed (non-critical): {str(e)}")
        return False


def lambda_handler(event, context):
    """Main Lambda handler with comprehensive error handling"""

    try:
        print("Starting school closings fetch...")

        # Fetch from both sources - each independently handles errors
        nbc_url = 'https://www.nbcconnecticut.com/weather/school-closings/'
        wfsb_url = 'https://webpubcontent.gray.tv/wfsb/xml/WFSBclosings.html?app_data=referer_override%3D'

        nbc_entries = get_closings_from_source(nbc_url, "NBC Connecticut")
        wfsb_entries = get_closings_from_source(wfsb_url, "WFSB")

        # Combine all entries
        all_entries = nbc_entries + wfsb_entries

        # Optional test hook: force a notification without changing state
        if isinstance(event, dict) and event.get('forceTest') is True:
            now_eastern = get_eastern_time()
            test_data = {
                'lastUpdated': now_eastern.strftime('%m/%d/%Y %I:%M:%S %p') + ' EST',
                'entries': [
                    {
                        "Name": "Test School",
                        "Status": "Closed (test)",
                        "UpdateTime": now_eastern.strftime("%m/%d/%Y %I:%M:%S %p") + " EST",
                        "Source": "Test Event"
                    }
                ]
            }
            send_notification(test_data['entries'], test_data['lastUpdated'])
            return {
                'statusCode': 200,
                'headers': {
                    'Content-Type': 'application/json',
                    'Access-Control-Allow-Origin': '*',
                    'Access-Control-Allow-Headers': 'Content-Type,Accept',
                    'Access-Control-Allow-Methods': 'GET,OPTIONS',
                    'Cache-Control': 'no-store, must-revalidate',
                    'Pragma': 'no-cache',
                    'Expires': '0'
                },
                'body': json.dumps(test_data)
            }

        print(f"Total entries found: {len(all_entries)}")

        # Create response data with Eastern time
        now_eastern = get_eastern_time()
        json_data = {
            'lastUpdated': now_eastern.strftime('%m/%d/%Y %I:%M:%S %p') + ' EST',
            'entries': all_entries
        }

        # Try to upload to S3, but don't fail if it doesn't work
        upload_to_s3(json_data)

        # Notification logic: one alert per storm, reset after 4 hours of no data
        state = load_state()
        notified = state.get('notified', False)

        if len(all_entries) > 0:
            state['last_nonempty_time'] = now_eastern.isoformat()
            if not notified:
                sent = send_notification(all_entries, json_data['lastUpdated'])
                if sent:
                    state['notified'] = True
        else:
            if notified and should_reset_notification(state, now_eastern, reset_hours=4):
                state['notified'] = False

        save_state(state)

        # Always return success with the data we have (even if empty)
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Accept',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'Cache-Control': 'no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0'
            },
            'body': json.dumps(json_data)
        }

    except Exception as e:
        # Catch-all error handler - return valid empty response
        print(f"Critical error in lambda_handler: {str(e)}")

        emergency_response = {
            'lastUpdated': get_eastern_time().strftime('%m/%d/%Y %I:%M:%S %p') + ' EST',
            'entries': []
        }

        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Accept',
                'Access-Control-Allow-Methods': 'GET,OPTIONS',
                'Cache-Control': 'no-store, must-revalidate',
                'Pragma': 'no-cache',
                'Expires': '0'
            },
            'body': json.dumps(emergency_response)
        }
