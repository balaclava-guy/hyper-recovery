//! Static asset serving

use axum::{
    http::{header, StatusCode},
    response::IntoResponse,
};

/// Serve the CSS stylesheet
pub async fn serve_css() -> impl IntoResponse {
    (
        StatusCode::OK,
        [(header::CONTENT_TYPE, "text/css")],
        CSS_CONTENT,
    )
}

const CSS_CONTENT: &str = r##"
/* Hyper Recovery WiFi Portal - Arcade Style */

:root {
    --primary: #0ea1fb;
    --accent: #48d7fb;
    --bg: #070c19;
    --bg-card: rgba(14, 161, 251, 0.1);
    --text: #ffffff;
    --text-dim: #8899aa;
    --error: #e94a57;
    --success: #4ade80;
    --warning: #efbe1d;
}

* {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
}

body {
    background-color: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    min-height: 100vh;
    /* CRT Scanline Effect */
    background-image: 
        linear-gradient(rgba(18, 16, 16, 0) 50%, rgba(0, 0, 0, 0.15) 50%),
        linear-gradient(90deg, rgba(255, 0, 0, 0.03), rgba(0, 255, 0, 0.01), rgba(0, 0, 255, 0.03));
    background-size: 100% 2px, 3px 100%;
}

.container {
    max-width: 480px;
    margin: 0 auto;
    padding: 16px;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
}

/* Header */
.header {
    text-align: center;
    padding: 24px 0;
    border-bottom: 2px solid var(--primary);
    margin-bottom: 16px;
}

.title {
    font-size: 1.5rem;
    font-weight: 800;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 3px;
    text-shadow: 0 0 10px var(--primary);
    margin-bottom: 4px;
}

.subtitle {
    font-size: 0.75rem;
    color: var(--text-dim);
    letter-spacing: 2px;
}

/* Status Bar */
.status-bar {
    padding: 12px 16px;
    border-radius: 4px;
    margin-bottom: 16px;
    text-align: center;
    font-weight: 500;
    transition: all 0.3s ease;
}

.status-waiting {
    background: var(--bg-card);
    border: 1px solid var(--primary);
}

.status-connecting {
    background: rgba(239, 190, 29, 0.2);
    border: 1px solid var(--warning);
    color: var(--warning);
    animation: pulse 1.5s infinite;
}

.status-connected {
    background: rgba(74, 222, 128, 0.2);
    border: 1px solid var(--success);
    color: var(--success);
}

.status-failed {
    background: rgba(233, 74, 87, 0.2);
    border: 1px solid var(--error);
    color: var(--error);
}

@keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.7; }
}

/* Network List */
.network-list {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 8px;
    overflow-y: auto;
    padding-bottom: 16px;
}

.network-card {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 16px;
    background: var(--bg-card);
    border: 1px solid var(--primary);
    border-radius: 4px;
    cursor: pointer;
    transition: all 0.2s ease;
    width: 100%;
    text-align: left;
    color: var(--text);
    font-size: 1rem;
}

.network-card:hover,
.network-card:focus {
    background: rgba(14, 161, 251, 0.2);
    border-color: var(--accent);
    box-shadow: 0 0 15px rgba(72, 215, 251, 0.3);
    transform: translateX(4px);
    outline: none;
}

.network-card:active {
    transform: translateX(2px) scale(0.99);
}

.network-info {
    display: flex;
    align-items: center;
    gap: 12px;
}

.lock-icon {
    font-size: 1.2rem;
}

.network-details {
    display: flex;
    flex-direction: column;
}

.ssid {
    font-weight: 600;
    margin-bottom: 2px;
}

.meta {
    font-size: 0.75rem;
    color: var(--text-dim);
    display: flex;
    align-items: center;
    gap: 8px;
}

.badge {
    background: var(--primary);
    color: var(--bg);
    padding: 2px 6px;
    border-radius: 2px;
    font-size: 0.65rem;
    font-weight: 600;
}

.badge.open {
    background: var(--success);
}

/* Signal Bars */
.signal {
    display: flex;
    align-items: flex-end;
    gap: 2px;
    height: 20px;
}

.bar {
    width: 4px;
    background: var(--primary);
    opacity: 0.3;
    border-radius: 1px;
}

.bar.filled {
    opacity: 1;
}

.signal-pct {
    font-size: 0.7rem;
    color: var(--text-dim);
    margin-left: 6px;
    min-width: 30px;
}

/* Manual Entry Button */
.manual-btn {
    padding: 14px;
    background: transparent;
    border: 1px dashed var(--primary);
    color: var(--primary);
    border-radius: 4px;
    cursor: pointer;
    font-size: 0.9rem;
    transition: all 0.2s ease;
    margin-top: 8px;
}

.manual-btn:hover {
    background: var(--bg-card);
    border-style: solid;
}

/* Modal */
.modal {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    bottom: 0;
    background: rgba(0, 0, 0, 0.8);
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 16px;
    z-index: 100;
}

.modal.hidden {
    display: none;
}

.modal-content {
    background: var(--bg);
    border: 2px solid var(--warning);
    border-radius: 8px;
    padding: 24px;
    width: 100%;
    max-width: 360px;
    box-shadow: 0 0 30px rgba(239, 190, 29, 0.3);
}

.modal-content h2 {
    color: var(--accent);
    margin-bottom: 8px;
    font-size: 1.1rem;
}

.modal-content p {
    color: var(--text-dim);
    margin-bottom: 16px;
    font-size: 0.9rem;
}

.input-group {
    display: flex;
    margin-bottom: 12px;
}

.input-group input {
    flex: 1;
    padding: 12px;
    background: rgba(255, 255, 255, 0.1);
    border: 1px solid var(--primary);
    border-radius: 4px 0 0 4px;
    color: var(--text);
    font-size: 1rem;
}

.input-group input:focus {
    outline: none;
    border-color: var(--accent);
    box-shadow: 0 0 10px rgba(72, 215, 251, 0.3);
}

.input-group input::placeholder {
    color: var(--text-dim);
}

.toggle-password {
    padding: 12px;
    background: var(--bg-card);
    border: 1px solid var(--primary);
    border-left: none;
    border-radius: 0 4px 4px 0;
    cursor: pointer;
    font-size: 1rem;
}

.input-group:only-child input,
.input-group input:only-child {
    border-radius: 4px;
}

.modal-actions {
    display: flex;
    gap: 12px;
    margin-top: 16px;
}

.btn-cancel,
.btn-connect {
    flex: 1;
    padding: 12px;
    border: none;
    border-radius: 4px;
    font-weight: 600;
    cursor: pointer;
    font-size: 0.9rem;
    transition: all 0.2s ease;
}

.btn-cancel {
    background: transparent;
    border: 1px solid var(--text-dim);
    color: var(--text-dim);
}

.btn-cancel:hover {
    border-color: var(--text);
    color: var(--text);
}

.btn-connect {
    background: var(--primary);
    color: var(--bg);
}

.btn-connect:hover {
    background: var(--accent);
    box-shadow: 0 0 15px rgba(72, 215, 251, 0.5);
}

.btn-connect:active {
    transform: scale(0.98);
}

/* Responsive */
@media (max-width: 360px) {
    .container {
        padding: 12px;
    }
    
    .title {
        font-size: 1.2rem;
    }
    
    .network-card {
        padding: 12px;
    }
}
"##;
