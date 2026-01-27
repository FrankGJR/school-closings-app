const API_URL = 'https://yr4zm4dy27.execute-api.us-east-1.amazonaws.com/Prod/';

// Register Service Worker for PWA functionality
if ('serviceWorker' in navigator) {
    navigator.serviceWorker.register('service-worker.js').catch(err => {
        console.log('Service Worker registration failed:', err);
    });
}

// DOM Elements
const refreshBtn = document.getElementById('refreshBtn');
const schoolList = document.getElementById('schoolList');
const loadingOverlay = document.getElementById('loadingOverlay');
const emptyState = document.getElementById('emptyState');
const errorState = document.getElementById('errorState');
const lastUpdatedEl = document.getElementById('lastUpdated');
const errorMessageEl = document.getElementById('errorMessage');
const retryBtn = document.getElementById('retryBtn');

// Event Listeners
refreshBtn.addEventListener('click', fetchClosings);
retryBtn.addEventListener('click', fetchClosings);

// Initial load
fetchClosings();

// Auto-refresh every 15 minutes (900000 ms)
setInterval(fetchClosings, 900000);

async function fetchClosings() {
    try {
        // Show loading state
        showLoading(true);
        hideStates();

        const response = await fetch(API_URL, {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
            },
            cache: 'no-store'
        });

        if (!response.ok) {
            throw new Error(`HTTP ${response.status}: ${response.statusText}`);
        }

        const data = await response.json();

        // Validate response structure
        if (!data.entries || !Array.isArray(data.entries)) {
            throw new Error('Invalid response format');
        }

        // Update last updated time
        lastUpdatedEl.textContent = data.lastUpdated || 'Unknown';

        // Display results
        if (data.entries.length === 0) {
            showEmpty();
        } else {
            displaySchools(data.entries);
        }

        // Remove loading state
        showLoading(false);

    } catch (error) {
        console.error('Error fetching closings:', error);
        showError(error.message);
        showLoading(false);
    }
}

function displaySchools(entries) {
    // Sort alphabetically by name
    const sorted = [...entries].sort((a, b) => a.Name.localeCompare(b.Name));

    schoolList.innerHTML = '';

    sorted.forEach((entry, index) => {
        const card = createSchoolCard(entry);
        schoolList.appendChild(card);

        // Stagger animation
        card.style.animationDelay = `${index * 50}ms`;
    });
}

function createSchoolCard(entry) {
    const card = document.createElement('div');
    card.className = 'school-card';

    // Determine status color and icon
    const statusLower = entry.Status.toLowerCase();
    let statusClass = 'status-other';
    let icon = '⏱️';

    if (statusLower.includes('closed')) {
        statusClass = 'status-closed';
        icon = '❌';
    } else if (statusLower.includes('delay')) {
        statusClass = 'status-delayed';
        icon = '⚠️';
    }

    card.innerHTML = `
        <div class="card-icon">${icon}</div>
        <div class="card-content">
            <div class="card-header">
                <div>
                    <div class="school-name">${escapeHtml(entry.Name)}</div>
                    <div class="school-status ${statusClass}">${escapeHtml(entry.Status)}</div>
                </div>
            </div>
            
            <div class="card-divider"></div>
            
            <div class="card-details">
                <div class="detail-item">
                    <svg class="detail-icon" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zm3.5-9c.83 0 1.5-.67 1.5-1.5S16.33 8 15.5 8 14 8.67 14 9.5s.67 1.5 1.5 1.5zm-7 0c.83 0 1.5-.67 1.5-1.5S9.33 8 8.5 8 7 8.67 7 9.5 7.67 11 8.5 11zm3.5 6.5c2.33 0 4.31-1.46 5.11-3.5H6.89c.8 2.04 2.78 3.5 5.11 3.5z"/>
                    </svg>
                    <span>${escapeHtml(entry.UpdateTime)}</span>
                </div>
                <div class="detail-item">
                    <svg class="detail-icon" viewBox="0 0 24 24" fill="currentColor">
                        <path d="M19.43 12.98c.04-.32.07-.64.07-.98s-.03-.66-.07-.98l2.11-1.65c.19-.15.24-.42.12-.64l-2-3.46c-.12-.22-.39-.3-.61-.22l-2.49 1c-.52-.4-1.08-.73-1.69-.98l-.38-2.65C14.46 2.18 14.25 2 14 2h-4c-.25 0-.46.18-.49.52l-.38 2.65c-.61.25-1.17.59-1.69.98l-2.49-1c-.23-.09-.49 0-.61.22l-2 3.46c-.13.22-.07.49.12.64l2.11 1.65c-.04.32-.07.65-.07.98s.03.66.07.98l-2.11 1.65c-.19.15-.24.42-.12.64l2 3.46c.12.22.39.3.61.22l2.49-1c.52.4 1.08.73 1.69.98l.38 2.65c.03.34.24.52.49.52h4c.25 0 .46-.18.49-.52l.38-2.65c.61-.25 1.17-.59 1.69-.98l2.49 1c.23.09.49 0 .61-.22l2-3.46c.12-.22.07-.49-.12-.64l-2.11-1.65zM12 15.5c-1.93 0-3.5-1.57-3.5-3.5s1.57-3.5 3.5-3.5 3.5 1.57 3.5 3.5-1.57 3.5-3.5 3.5z"/>
                    </svg>
                    <span>${escapeHtml(entry.Source)}</span>
                </div>
            </div>
        </div>
    `;

    return card;
}

function showLoading(show) {
    loadingOverlay.style.display = show ? 'flex' : 'none';
    if (show) {
        refreshBtn.classList.add('spinning');
    } else {
        refreshBtn.classList.remove('spinning');
    }
}

function showEmpty() {
    hideStates();
    emptyState.style.display = 'flex';
    schoolList.innerHTML = '';
}

function showError(message) {
    hideStates();
    errorState.style.display = 'flex';
    errorMessageEl.textContent = message || 'Unable to load school closings. Please try again.';
    schoolList.innerHTML = '';
}

function hideStates() {
    emptyState.style.display = 'none';
    errorState.style.display = 'none';
    schoolList.innerHTML = '';
}

// Security: Escape HTML to prevent XSS
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// Request notification permission for PWA
if ('Notification' in window && Notification.permission === 'default') {
    Notification.requestPermission();
}
