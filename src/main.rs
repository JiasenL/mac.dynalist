//! Dynalist for macOS — a tiny native wrapper around https://dynalist.io
//! built with tao (windowing) + wry (WKWebView) + muda (menu bar).

use muda::{
    accelerator::{Accelerator, Code, Modifiers},
    Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu,
};
use tao::{
    dpi::LogicalSize,
    event::{Event, StartCause, WindowEvent},
    event_loop::{ControlFlow, EventLoopBuilder},
    window::WindowBuilder,
};
use wry::{NewWindowResponse, WebViewBuilder};

const HOME_URL: &str = "https://dynalist.io/";

/// URLs that should stay inside the app window; everything else opens in the default browser.
fn is_internal(url: &str) -> bool {
    let host = url
        .split("://")
        .nth(1)
        .and_then(|rest| rest.split(['/', '?', '#']).next())
        .unwrap_or("");
    url.starts_with("about:")
        || url.starts_with("blob:")
        || url.starts_with("data:")
        || host == "dynalist.io"
        || host.ends_with(".dynalist.io")
        // Google sign-in flow
        || host == "accounts.google.com"
        || host.ends_with(".google.com") && url.contains("/o/oauth2")
}

fn open_external(url: &str) {
    let _ = std::process::Command::new("open").arg(url).spawn();
}

enum UserEvent {
    Menu(MenuEvent),
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();

    // Forward menu events into the tao event loop.
    let proxy = event_loop.create_proxy();
    MenuEvent::set_event_handler(Some(move |e| {
        let _ = proxy.send_event(UserEvent::Menu(e));
    }));

    // ---- Menu bar -------------------------------------------------------
    let menu = Menu::new();

    let app_menu = Submenu::new("Dynalist", true);
    app_menu.append_items(&[
        &PredefinedMenuItem::about(None, None),
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::services(None),
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::hide(None),
        &PredefinedMenuItem::hide_others(None),
        &PredefinedMenuItem::show_all(None),
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::quit(None),
    ])?;

    let edit_menu = Submenu::new("Edit", true);
    edit_menu.append_items(&[
        &PredefinedMenuItem::undo(None),
        &PredefinedMenuItem::redo(None),
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::cut(None),
        &PredefinedMenuItem::copy(None),
        &PredefinedMenuItem::paste(None),
        &PredefinedMenuItem::select_all(None),
    ])?;

    let cmd = Modifiers::META;
    let reload = MenuItem::new("Reload", true, Some(Accelerator::new(cmd, Code::KeyR)));
    let home = MenuItem::new(
        "Home",
        true,
        Some(Accelerator::new(Modifiers::META | Modifiers::SHIFT, Code::KeyH)),
    );
    let back = MenuItem::new("Back", true, Some(Accelerator::new(cmd, Code::BracketLeft)));
    let forward = MenuItem::new("Forward", true, Some(Accelerator::new(cmd, Code::BracketRight)));
    let zoom_in = MenuItem::new("Zoom In", true, Some(Accelerator::new(cmd, Code::Equal)));
    let zoom_out = MenuItem::new("Zoom Out", true, Some(Accelerator::new(cmd, Code::Minus)));
    let zoom_reset = MenuItem::new("Actual Size", true, Some(Accelerator::new(cmd, Code::Digit0)));

    let view_menu = Submenu::new("View", true);
    view_menu.append_items(&[
        &reload,
        &home,
        &PredefinedMenuItem::separator(),
        &back,
        &forward,
        &PredefinedMenuItem::separator(),
        &zoom_in,
        &zoom_out,
        &zoom_reset,
        &PredefinedMenuItem::separator(),
        &PredefinedMenuItem::fullscreen(None),
    ])?;

    let window_menu = Submenu::new("Window", true);
    window_menu.append_items(&[
        &PredefinedMenuItem::minimize(None),
        &PredefinedMenuItem::maximize(None),
        &PredefinedMenuItem::close_window(None),
    ])?;

    menu.append_items(&[&app_menu, &edit_menu, &view_menu, &window_menu])?;

    // ---- Window + WebView ----------------------------------------------
    let window = WindowBuilder::new()
        .with_title("Dynalist")
        .with_inner_size(LogicalSize::new(1200.0, 800.0))
        .with_min_inner_size(LogicalSize::new(480.0, 360.0))
        .build(&event_loop)
        .expect("failed to create window");

    let webview = WebViewBuilder::new()
        .with_url(HOME_URL)
        .with_devtools(cfg!(debug_assertions))
        .with_back_forward_navigation_gestures(true)
        .with_navigation_handler(|url| {
            if is_internal(&url) {
                true
            } else {
                open_external(&url);
                false
            }
        })
        .with_new_window_req_handler(|url, _features| {
            open_external(&url);
            NewWindowResponse::Deny
        })
        .build(&window)?;

    let mut zoom: f64 = 1.0;

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        match event {
            Event::NewEvents(StartCause::Init) => {
                menu.init_for_nsapp();
                window_menu.set_as_windows_menu_for_nsapp();
            }
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                *control_flow = ControlFlow::Exit;
            }
            Event::UserEvent(UserEvent::Menu(e)) => {
                let id = e.id();
                if id == reload.id() {
                    let _ = webview.reload();
                } else if id == home.id() {
                    let _ = webview.load_url(HOME_URL);
                } else if id == back.id() {
                    let _ = webview.evaluate_script("history.back()");
                } else if id == forward.id() {
                    let _ = webview.evaluate_script("history.forward()");
                } else if id == zoom_in.id() {
                    zoom = (zoom + 0.1).min(3.0);
                    let _ = webview.zoom(zoom);
                } else if id == zoom_out.id() {
                    zoom = (zoom - 0.1).max(0.5);
                    let _ = webview.zoom(zoom);
                } else if id == zoom_reset.id() {
                    zoom = 1.0;
                    let _ = webview.zoom(zoom);
                }
            }
            _ => {}
        }
    });
}
