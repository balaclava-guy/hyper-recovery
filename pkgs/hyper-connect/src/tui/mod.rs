//! Ratatui TUI for WiFi setup

mod ui;
mod widgets;

use crate::controller::{ipc, ConnectionStatus, WifiStateSnapshot};
use anyhow::Result;
use crossterm::{
    event::{self, DisableMouseCapture, EnableMouseCapture, Event, KeyCode, KeyEventKind},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{backend::CrosstermBackend, Terminal};
use std::io;
use std::time::Duration;

/// TUI application state
pub struct App {
    socket_path: String,
    state: Option<WifiStateSnapshot>,
    selected_network: usize,
    input_mode: InputMode,
    password_input: String,
    password_visible: bool,
    error_message: Option<String>,
    should_quit: bool,
}

#[derive(Debug, Clone, PartialEq)]
enum InputMode {
    Normal,
    Password,
    ManualSsid,
}

impl App {
    fn new(socket_path: String) -> Self {
        Self {
            socket_path,
            state: None,
            selected_network: 0,
            input_mode: InputMode::Normal,
            password_input: String::new(),
            password_visible: false,
            error_message: None,
            should_quit: false,
        }
    }

    async fn refresh_state(&mut self) {
        match ipc::get_status(&self.socket_path).await {
            Ok(state) => {
                self.state = Some(state);
                self.error_message = None;
            }
            Err(e) => {
                self.error_message = Some(format!("Failed to connect to daemon: {}", e));
            }
        }
    }

    fn selected_ssid(&self) -> Option<String> {
        self.state.as_ref().and_then(|s| {
            s.available_networks
                .get(self.selected_network)
                .map(|n| n.ssid.clone())
        })
    }

    async fn connect_to_selected(&mut self) {
        if let Some(ssid) = self.selected_ssid() {
            // TUI always saves credentials by default
            match ipc::send_connect(&self.socket_path, &ssid, &self.password_input, true).await {
                Ok(()) => {
                    self.input_mode = InputMode::Normal;
                    self.password_input.clear();
                }
                Err(e) => {
                    self.error_message = Some(format!("Connection failed: {}", e));
                }
            }
        }
    }
}

/// Run the TUI
pub async fn run_tui(socket_path: &str) -> Result<()> {
    // Setup terminal
    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, EnableMouseCapture)?;
    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    // Create app
    let mut app = App::new(socket_path.to_string());

    // Initial state fetch
    app.refresh_state().await;

    // Main loop
    let result = run_app(&mut terminal, &mut app).await;

    // Restore terminal
    disable_raw_mode()?;
    execute!(
        terminal.backend_mut(),
        LeaveAlternateScreen,
        DisableMouseCapture
    )?;
    terminal.show_cursor()?;

    result
}

async fn run_app(
    terminal: &mut Terminal<CrosstermBackend<io::Stdout>>,
    app: &mut App,
) -> Result<()> {
    let tick_rate = Duration::from_millis(250);
    let mut last_tick = std::time::Instant::now();

    loop {
        // Draw UI
        terminal.draw(|f| ui::draw(f, app))?;

        // Handle input with timeout
        let timeout = tick_rate.saturating_sub(last_tick.elapsed());
        if crossterm::event::poll(timeout)? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match app.input_mode {
                        InputMode::Normal => match key.code {
                            KeyCode::Char('q') | KeyCode::Esc => {
                                app.should_quit = true;
                            }
                            KeyCode::Up | KeyCode::Char('k') => {
                                if app.selected_network > 0 {
                                    app.selected_network -= 1;
                                }
                            }
                            KeyCode::Down | KeyCode::Char('j') => {
                                if let Some(state) = &app.state {
                                    if app.selected_network
                                        < state.available_networks.len().saturating_sub(1)
                                    {
                                        app.selected_network += 1;
                                    }
                                }
                            }
                            KeyCode::Enter => {
                                if let Some(state) = &app.state {
                                    if let Some(network) =
                                        state.available_networks.get(app.selected_network)
                                    {
                                        if network.is_secured {
                                            app.input_mode = InputMode::Password;
                                        } else {
                                            // Connect to open network
                                            app.password_input.clear();
                                            app.connect_to_selected().await;
                                        }
                                    }
                                }
                            }
                            KeyCode::Char('m') => {
                                app.input_mode = InputMode::ManualSsid;
                            }
                            KeyCode::Char('r') => {
                                app.refresh_state().await;
                            }
                            _ => {}
                        },
                        InputMode::Password => match key.code {
                            KeyCode::Esc => {
                                app.input_mode = InputMode::Normal;
                                app.password_input.clear();
                            }
                            KeyCode::Enter => {
                                app.connect_to_selected().await;
                            }
                            KeyCode::Backspace => {
                                app.password_input.pop();
                            }
                            KeyCode::Char(c) => {
                                app.password_input.push(c);
                            }
                            KeyCode::Tab => {
                                app.password_visible = !app.password_visible;
                            }
                            _ => {}
                        },
                        InputMode::ManualSsid => match key.code {
                            KeyCode::Esc => {
                                app.input_mode = InputMode::Normal;
                                app.password_input.clear();
                            }
                            KeyCode::Enter => {
                                // TODO: Handle manual SSID entry
                                app.input_mode = InputMode::Normal;
                            }
                            KeyCode::Backspace => {
                                app.password_input.pop();
                            }
                            KeyCode::Char(c) => {
                                app.password_input.push(c);
                            }
                            _ => {}
                        },
                    }
                }
            }
        }

        // Tick - refresh state periodically
        if last_tick.elapsed() >= tick_rate {
            app.refresh_state().await;
            last_tick = std::time::Instant::now();
        }

        // Check if connected or should quit
        if app.should_quit {
            break;
        }

        if let Some(state) = &app.state {
            if state.status == ConnectionStatus::Connected {
                // Show success briefly then exit
                terminal.draw(|f| ui::draw(f, app))?;
                tokio::time::sleep(Duration::from_secs(3)).await;
                break;
            }
        }
    }

    Ok(())
}
