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
:root {
  --background: 222 32% 10%;
  --foreground: 210 24% 96%;
  --card: 223 30% 14%;
  --card-foreground: 210 24% 96%;
  --primary: 197 85% 63%;
  --primary-foreground: 222 30% 11%;
  --secondary: 216 25% 22%;
  --secondary-foreground: 210 24% 96%;
  --accent: 217 24% 26%;
  --accent-foreground: 210 24% 96%;
  --muted: 217 24% 22%;
  --muted-foreground: 215 18% 70%;
  --destructive: 0 62% 47%;
  --destructive-foreground: 0 0% 100%;
  --border: 217 24% 30%;
  --input: 217 24% 30%;
  --ring: 197 85% 63%;
  --radius: 12px;
}

* {
  box-sizing: border-box;
}

html,
body {
  margin: 0;
  min-height: 100%;
}

body {
  color: hsl(var(--foreground));
  background:
    radial-gradient(1200px 700px at 10% -20%, hsla(var(--primary), 0.22), transparent 50%),
    radial-gradient(900px 700px at 110% 20%, hsla(var(--accent), 0.2), transparent 48%),
    hsl(var(--background));
  font-family: "IBM Plex Sans", "Avenir Next", "Segoe UI", sans-serif;
  line-height: 1.4;
}

.portal-root {
  min-height: 100vh;
  padding: 18px;
  display: flex;
  align-items: flex-start;
  justify-content: center;
}

.portal-shell {
  width: min(760px, 100%);
  background: hsla(var(--card), 0.9);
  color: hsl(var(--card-foreground));
  border: 1px solid hsl(var(--border));
  border-radius: var(--radius);
  box-shadow: 0 18px 40px rgba(5, 16, 35, 0.15);
  backdrop-filter: blur(10px);
}

.portal-header {
  border-bottom: 1px solid hsl(var(--border));
  padding: 20px 20px 16px;
}

.portal-title {
  margin: 0;
  font-size: 1.4rem;
  font-weight: 700;
  letter-spacing: 0.02em;
}

.portal-subtitle {
  margin-top: 6px;
  color: hsl(var(--muted-foreground));
  font-size: 0.92rem;
}

.portal-content {
  padding: 18px 20px 20px;
  display: grid;
  gap: 12px;
}

.portal-status {
  border: 1px solid hsl(var(--border));
  background: hsla(var(--muted), 0.55);
  border-radius: calc(var(--radius) - 4px);
  padding: 12px 14px;
}

.portal-status.state-waiting,
.portal-status[data-state="waiting"] {
  border-color: hsl(var(--border));
}

.portal-status.state-connecting,
.portal-status[data-state="connecting"] {
  border-color: hsl(42 92% 48%);
  background: hsla(42 92% 48%, 0.15);
}

.portal-status.state-connected,
.portal-status[data-state="connected"] {
  border-color: hsl(148 67% 38%);
  background: hsla(148 67% 38%, 0.15);
}

.portal-status.state-failed,
.portal-status[data-state="failed"] {
  border-color: hsl(var(--destructive));
  background: hsla(var(--destructive), 0.12);
}

.portal-status-title {
  margin: 0;
  font-size: 0.98rem;
}

.portal-status-detail {
  margin-top: 4px;
  color: hsl(var(--muted-foreground));
  font-size: 0.86rem;
}

.portal-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
}

.portal-action-btn {
  border: 1px solid hsl(var(--border));
  border-radius: calc(var(--radius) - 6px);
  padding: 10px 12px;
  min-height: 40px;
  background: hsla(var(--card), 0.9);
  color: hsl(var(--foreground));
  font-weight: 600;
}

.portal-action-btn:hover {
  background: hsla(var(--accent), 0.8);
}

.network-list {
  display: grid;
  gap: 10px;
  max-height: 52vh;
  overflow: auto;
}

.network-row {
  width: 100%;
  border: 1px solid hsl(var(--border));
  background: hsla(var(--card), 0.92);
  color: hsl(var(--foreground));
  border-radius: calc(var(--radius) - 4px);
  padding: 12px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  gap: 12px;
  text-align: left;
  cursor: pointer;
  transition: transform 120ms ease, border-color 120ms ease, background 120ms ease;
}

.network-row:hover,
.network-row:focus-visible {
  border-color: hsl(var(--primary));
  background: hsla(var(--accent), 0.55);
  transform: translateY(-1px);
  outline: none;
}

.network-main {
  min-width: 0;
}

.network-ssid {
  display: block;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.network-meta {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-top: 5px;
}

.network-channel {
  font-size: 0.78rem;
  color: hsl(var(--muted-foreground));
}

.network-badge {
  border-radius: 999px;
  border: 1px solid hsl(var(--border));
  padding: 2px 8px;
  font-size: 0.72rem;
}

.signal-wrap {
  display: flex;
  align-items: center;
  gap: 8px;
}

.signal-meter {
  width: 56px;
  height: 7px;
  border-radius: 999px;
  background: hsla(var(--muted), 0.9);
  overflow: hidden;
}

.signal-meter > span {
  display: block;
  height: 100%;
  background: linear-gradient(90deg, hsl(var(--primary)), hsl(var(--accent-foreground)));
}

.signal-value {
  min-width: 34px;
  text-align: right;
  font-size: 0.78rem;
  color: hsl(var(--muted-foreground));
}

.empty-state {
  margin: 0;
  border: 1px dashed hsl(var(--border));
  background: hsla(var(--muted), 0.4);
  border-radius: calc(var(--radius) - 4px);
  padding: 18px;
  font-size: 0.9rem;
  color: hsl(var(--muted-foreground));
  text-align: center;
}

.modal {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.58);
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 16px;
  z-index: 30;
}

.modal.hidden {
  display: none;
}

.modal-card {
  width: min(460px, 100%);
  background: hsl(var(--card));
  border: 1px solid hsl(var(--border));
  border-radius: var(--radius);
  box-shadow: 0 20px 50px rgba(0, 0, 0, 0.25);
}

.modal-header {
  padding: 16px 16px 10px;
}

.modal-title {
  margin: 0;
  font-size: 1.05rem;
}

.modal-subtitle {
  margin-top: 6px;
  color: hsl(var(--muted-foreground));
  font-size: 0.84rem;
}

.modal-content {
  padding: 0 16px 16px;
}

.portal-form {
  display: grid;
  gap: 10px;
}

.password-row {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 8px;
  align-items: center;
}

.portal-input {
  width: 100%;
  border: 1px solid hsl(var(--input));
  border-radius: calc(var(--radius) - 6px);
  min-height: 40px;
  padding: 10px 11px;
  font-size: 0.95rem;
  background: hsl(var(--background));
  color: hsl(var(--foreground));
}

.portal-input:focus {
  outline: 2px solid hsla(var(--ring), 0.45);
  outline-offset: 1px;
}

.toggle-btn {
  min-height: 40px;
  border: 1px solid hsl(var(--border));
  border-radius: calc(var(--radius) - 6px);
  background: hsla(var(--muted), 0.7);
  color: hsl(var(--foreground));
  padding: 0 10px;
}

.checkbox-row {
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 0.86rem;
  color: hsl(var(--muted-foreground));
}

.modal-actions {
  display: flex;
  gap: 10px;
  margin-top: 2px;
}

.plain-btn {
  flex: 1;
  min-height: 40px;
  border-radius: calc(var(--radius) - 6px);
  border: 1px solid hsl(var(--border));
  font-weight: 600;
}

.plain-btn.primary {
  background: hsl(var(--primary));
  color: hsl(var(--primary-foreground));
  border-color: hsl(var(--primary));
}

.plain-btn.secondary {
  background: transparent;
  color: hsl(var(--foreground));
}

.plain-btn:hover,
.toggle-btn:hover {
  filter: brightness(1.03);
}

/* Light utility compatibility for shadcn defaults used by component internals. */
[class~="space-y-1"] > * + * {
  margin-top: 0.25rem;
}

[class~="text-destructive"] {
  color: hsl(var(--destructive));
}

@media (max-width: 640px) {
  .portal-root {
    padding: 10px;
  }

  .portal-header,
  .portal-content {
    padding-left: 14px;
    padding-right: 14px;
  }

  .modal-actions {
    flex-direction: column;
  }

  .plain-btn {
    width: 100%;
  }
}
"##;
