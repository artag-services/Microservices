mod domain;
mod application;
mod infrastructure;
mod presentation;

use std::sync::Arc;
use axum::{routing::post, Router};
use tower_http::cors::CorsLayer;

use crate::application::scrape_usecase::ScrapeUseCase;
use crate::infrastructure::http::reqwest_adapter::ReqwestClient;
use crate::infrastructure::parser::regex_cleaner::RegexCleaner;
use crate::infrastructure::parser::scraper_adapter::ScraperParser;

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "scraper_rs=info".into()),
        )
        .init();

    let http_client = Arc::new(ReqwestClient::new());
    let parser = Arc::new(ScraperParser);
    let cleaner = Arc::new(RegexCleaner);
    let use_case = Arc::new(ScrapeUseCase::new(http_client, parser, cleaner));

    let app = Router::new()
        .route("/scrape", post(presentation::routes::handle_scrape))
        .route("/health", post(|| async { "OK" }))
        .layer(CorsLayer::permissive())
        .with_state(use_case);

    let port = std::env::var("PORT").unwrap_or_else(|_| "3009".into());
    let addr: std::net::SocketAddr = format!("0.0.0.0:{}", port)
        .parse()
        .expect("Invalid address");

    tracing::info!("Starting scraper-rs on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}
