//! TUI rendering

use super::{App, InputMode};
use crate::controller::ConnectionStatus;
use ratatui::{
    layout::{Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, Borders, Clear, List, ListItem, Paragraph, Wrap},
    Frame,
};

// Hyper Recovery brand colors
const PRIMARY: Color = Color::Rgb(14, 161, 251); // #0ea1fb
const ACCENT: Color = Color::Rgb(72, 215, 251); // #48d7fb
const BG_DARK: Color = Color::Rgb(7, 12, 25); // #070c19
const ERROR: Color = Color::Rgb(233, 74, 87); // #e94a57
const SUCCESS: Color = Color::Rgb(74, 222, 128); // #4ade80
const WARNING: Color = Color::Rgb(239, 190, 29); // #efbe1d

pub fn draw(f: &mut Frame, app: &App) {
    let size = f.area();
    let backdrop = Block::default().style(Style::default().bg(Color::Black));
    f.render_widget(backdrop, size);

    let panel = centered_box(size, 104, 30);
    f.render_widget(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(PRIMARY))
            .style(Style::default().bg(BG_DARK)),
        panel,
    );

    let inner = inset(panel, 1);

    // Main layout
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3), // Header
            Constraint::Min(10),   // Content
            Constraint::Length(3), // Footer
        ])
        .split(inner);

    draw_header(f, chunks[0], app);
    draw_content(f, chunks[1], app);
    draw_footer(f, chunks[2], app);

    // Draw modal if in password mode
    if app.input_mode == InputMode::Password {
        draw_password_modal(f, app);
    }
}

fn draw_header(f: &mut Frame, area: Rect, app: &App) {
    let status_text = match app.state.as_ref().map(|s| &s.status) {
        Some(ConnectionStatus::Connected) => ("CONNECTED", SUCCESS),
        Some(ConnectionStatus::Connecting) => ("CONNECTING...", WARNING),
        Some(ConnectionStatus::SwitchingBackend) => ("SWITCHING BACKEND...", WARNING),
        Some(ConnectionStatus::Scanning) => ("SCANNING...", ACCENT),
        Some(ConnectionStatus::Failed) => ("FAILED", ERROR),
        Some(ConnectionStatus::AwaitingCredentials) => ("AWAITING CREDENTIALS", PRIMARY),
        _ => ("INITIALIZING", Color::Gray),
    };

    let backend_text = if let Some(state) = &app.state {
        if let Some(backend) = state.wifi_backend {
            format!(" | {}", match backend {
                crate::controller::WifiBackend::Iwd => "IWD",
                crate::controller::WifiBackend::WpaSupplicant => "WPA_SUPPLICANT",
            })
        } else {
            String::new()
        }
    } else {
        String::new()
    };

    let header = Paragraph::new(Line::from(vec![
        Span::styled(
            "HYPER RECOVERY",
            Style::default().fg(ACCENT).add_modifier(Modifier::BOLD),
        ),
        Span::raw("  ::  "),
        Span::styled("WIFI SETUP", Style::default().fg(PRIMARY)),
        Span::styled(&backend_text, Style::default().fg(Color::DarkGray)),
        Span::raw("                        "),
        Span::styled(
            format!("[ {} ]", status_text.0),
            Style::default().fg(status_text.1),
        ),
    ]))
    .block(
        Block::default()
            .borders(Borders::ALL)
            .border_style(Style::default().fg(PRIMARY)),
    );

    f.render_widget(header, area);
}

fn draw_content(f: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage(60), // Network list
            Constraint::Percentage(40), // Details/QR
        ])
        .split(area);

    draw_network_list(f, chunks[0], app);
    draw_details_panel(f, chunks[1], app);
}

fn draw_network_list(f: &mut Frame, area: Rect, app: &App) {
    let networks: Vec<ListItem> = app
        .state
        .as_ref()
        .map(|s| &s.available_networks)
        .unwrap_or(&vec![])
        .iter()
        .enumerate()
        .map(|(i, network)| {
            let lock = if network.is_secured { "🔒" } else { "🔓" };
            let signal_bar = signal_to_bar(network.signal_strength);
            let selected = i == app.selected_network;

            let style = if selected {
                Style::default().fg(ACCENT).add_modifier(Modifier::BOLD)
            } else {
                Style::default().fg(Color::White)
            };

            let prefix = if selected { "> " } else { "  " };

            ListItem::new(Line::from(vec![
                Span::styled(prefix, style),
                Span::styled(lock, style),
                Span::styled(format!(" {:<20}", network.ssid), style),
                Span::styled(
                    format!(" [{}] {:>3}%", signal_bar, network.signal_strength),
                    Style::default().fg(signal_color(network.signal_strength)),
                ),
                Span::styled(
                    format!("  CH{}", network.channel),
                    Style::default().fg(Color::DarkGray),
                ),
            ]))
        })
        .collect();

    let list = List::new(networks).block(
        Block::default()
            .title(" SELECT NETWORK ")
            .borders(Borders::ALL)
            .border_style(Style::default().fg(PRIMARY)),
    );

    f.render_widget(list, area);
}

fn draw_details_panel(f: &mut Frame, area: Rect, app: &App) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(8), // Network details
            Constraint::Min(6),    // QR code / portal info
        ])
        .split(area);

    // Network details
    let details = if let Some(state) = &app.state {
        if let Some(network) = state.available_networks.get(app.selected_network) {
            vec![
                Line::from(vec![
                    Span::styled("SSID: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(&network.ssid, Style::default().fg(Color::White)),
                ]),
                Line::from(vec![
                    Span::styled("BSSID: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(&network.bssid, Style::default().fg(Color::White)),
                ]),
                Line::from(vec![
                    Span::styled("Security: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(&network.security_type, Style::default().fg(Color::White)),
                ]),
                Line::from(vec![
                    Span::styled("Channel: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(
                        format!("{}", network.channel),
                        Style::default().fg(Color::White),
                    ),
                ]),
            ]
        } else {
            vec![Line::from("No network selected")]
        }
    } else {
        vec![Line::from("Loading...")]
    };

    let details_widget = Paragraph::new(details).block(
        Block::default()
            .title(" NETWORK DETAILS ")
            .borders(Borders::ALL)
            .border_style(Style::default().fg(PRIMARY)),
    );

    f.render_widget(details_widget, chunks[0]);

    // Portal info
    let portal_info = if let Some(state) = &app.state {
        if state.ap_running {
            let url = state.portal_url.as_deref().unwrap_or("http://192.168.42.1");
            vec![
                Line::from(Span::styled(
                    "CAPTIVE PORTAL ACTIVE",
                    Style::default().fg(SUCCESS),
                )),
                Line::from(""),
                Line::from(vec![
                    Span::styled("Connect to: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(
                        state.ap_ssid.as_deref().unwrap_or("HyperRecovery"),
                        Style::default().fg(ACCENT),
                    ),
                ]),
                Line::from(""),
                Line::from(vec![
                    Span::styled("Then visit: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(url, Style::default().fg(PRIMARY)),
                ]),
            ]
        } else if state.status == ConnectionStatus::Connected {
            vec![
                Line::from(Span::styled(
                    "CONNECTED!",
                    Style::default().fg(SUCCESS).add_modifier(Modifier::BOLD),
                )),
                Line::from(""),
                Line::from(vec![
                    Span::styled("Network: ", Style::default().fg(Color::DarkGray)),
                    Span::styled(
                        state.connected_ssid.as_deref().unwrap_or("Unknown"),
                        Style::default().fg(Color::White),
                    ),
                ]),
            ]
        } else {
            vec![Line::from("Waiting...")]
        }
    } else {
        vec![Line::from("Connecting to daemon...")]
    };

    let portal_widget = Paragraph::new(portal_info)
        .block(
            Block::default()
                .title(" STATUS ")
                .borders(Borders::ALL)
                .border_style(Style::default().fg(PRIMARY)),
        )
        .wrap(Wrap { trim: true });

    f.render_widget(portal_widget, chunks[1]);
}

fn draw_footer(f: &mut Frame, area: Rect, app: &App) {
    let help_text = match app.input_mode {
        InputMode::Normal => {
            "[↑/↓] Select   [Enter] Connect   [B] Switch Backend   [R] Refresh   [Q] Quit"
        }
        InputMode::Password => "[Enter] Submit   [Tab] Show/Hide   [Esc] Cancel",
        InputMode::ManualSsid => "[Enter] Submit   [Esc] Cancel",
    };

    let footer = Paragraph::new(help_text)
        .style(Style::default().fg(Color::DarkGray))
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(Style::default().fg(PRIMARY)),
        );

    f.render_widget(footer, area);
}

fn draw_password_modal(f: &mut Frame, app: &App) {
    let area = centered_rect(50, 30, f.area());

    // Clear the area
    f.render_widget(Clear, area);

    let ssid = app.selected_ssid().unwrap_or_default();

    let password_display = if app.password_visible {
        app.password_input.clone()
    } else {
        "*".repeat(app.password_input.len())
    };

    let content = vec![
        Line::from(""),
        Line::from(vec![
            Span::styled("ENTER PASSWORD FOR: ", Style::default().fg(Color::DarkGray)),
            Span::styled(&ssid, Style::default().fg(ACCENT)),
        ]),
        Line::from(""),
        Line::from(vec![
            Span::styled("> ", Style::default().fg(PRIMARY)),
            Span::styled(
                format!("{}_", password_display),
                Style::default().fg(Color::White),
            ),
        ]),
        Line::from(""),
        Line::from(Span::styled(
            "[Enter] Confirm    [Tab] Show/Hide    [Esc] Cancel",
            Style::default().fg(Color::DarkGray),
        )),
    ];

    let modal = Paragraph::new(content).block(
        Block::default()
            .title(" PASSWORD REQUIRED ")
            .borders(Borders::ALL)
            .border_style(Style::default().fg(WARNING))
            .style(Style::default().bg(BG_DARK)),
    );

    f.render_widget(modal, area);
}

fn signal_to_bar(signal: u8) -> String {
    let bars = (signal as f32 / 25.0).ceil() as usize;
    let filled = "█".repeat(bars.min(4));
    let empty = "░".repeat(4 - bars.min(4));
    format!("{}{}", filled, empty)
}

fn signal_color(signal: u8) -> Color {
    match signal {
        80..=100 => SUCCESS,
        50..=79 => PRIMARY,
        30..=49 => WARNING,
        _ => ERROR,
    }
}

fn centered_rect(percent_x: u16, percent_y: u16, r: Rect) -> Rect {
    let popup_layout = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Percentage((100 - percent_y) / 2),
            Constraint::Percentage(percent_y),
            Constraint::Percentage((100 - percent_y) / 2),
        ])
        .split(r);

    Layout::default()
        .direction(Direction::Horizontal)
        .constraints([
            Constraint::Percentage((100 - percent_x) / 2),
            Constraint::Percentage(percent_x),
            Constraint::Percentage((100 - percent_x) / 2),
        ])
        .split(popup_layout[1])[1]
}

fn centered_box(area: Rect, max_width: u16, max_height: u16) -> Rect {
    let available_width = area.width.saturating_sub(2).max(1);
    let available_height = area.height.saturating_sub(2).max(1);
    let width = available_width.min(max_width);
    let height = available_height.min(max_height);

    Rect {
        x: area.x + (area.width.saturating_sub(width)) / 2,
        y: area.y + (area.height.saturating_sub(height)) / 2,
        width,
        height,
    }
}

fn inset(area: Rect, padding: u16) -> Rect {
    let double = padding.saturating_mul(2);
    Rect {
        x: area.x.saturating_add(padding),
        y: area.y.saturating_add(padding),
        width: area.width.saturating_sub(double).max(1),
        height: area.height.saturating_sub(double).max(1),
    }
}
