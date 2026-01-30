import json
import re
import urllib.request
import boto3
from datetime import datetime
from zoneinfo import ZoneInfo

# AWS S3 client
s3_client = boto3.client('s3')
BUCKET_NAME = 'cardinal-driving-school-closings'
JSON_FILE_KEY = 'school_closings.json'

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
            pattern = r'<FONT\s+CLASS="orgname"[^>]*>(.*?)</FONT>[^:]*:\s*<FONT\s+CLASS="status"[^<]+</FONT>'
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

        print(f"Total entries found: {len(all_entries)}")

        # Create response data with Eastern time
        json_data = {
            'lastUpdated': get_eastern_time().strftime('%m/%d/%Y %I:%M:%S %p') + ' EST',
            'entries': all_entries
        }

        # Try to upload to S3, but don't fail if it doesn't work
        upload_to_s3(json_data)

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
