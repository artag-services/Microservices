mod scraper;

use axum::{http::StatusCode, routing::post, Json, Router};
use serde::Deserialize;
use std::net::SocketAddr;
use tower_http::cors::CorsLayer;

#[derive(Deserialize)]
struct ScrapeRequest {
    url: String,
    timeout_ms: Option<u64>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "scraper_rs=info".into()),
        )
        .init();

    let app = Router::new()
        .route("/scrape", post(handle_scrape))
        .route("/health", post(|| async { "OK" }))
        .layer(CorsLayer::permissive());

    let port = std::env::var("PORT").unwrap_or_else(|_| "3009".into());
    let addr: SocketAddr = format!("0.0.0.0:{}", port)
        .parse()
        .expect("Invalid address");

    tracing::info!("Starting scraper-rs on {}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await.unwrap();
    axum::serve(listener, app).await.unwrap();
}

async fn handle_scrape(
    Json(req): Json<ScrapeRequest>,
) -> Result<Json<scraper::ScrapeResponse>, (StatusCode, String)> {
    let timeout_ms = req.timeout_ms.unwrap_or(30_000);

    tracing::info!("Scraping url={} timeout={}ms", req.url, timeout_ms);

    match scraper::scrape_url(&req.url, timeout_ms).await {
        Ok(result) => {
            tracing::info!(
                "Scraped url={} title={:?} sections={} links={} text_len={}",
                req.url,
                result.title.chars().take(60).collect::<String>(),
                result.sections.len(),
                result.links.len(),
                result.text.len()
            );
            Ok(Json(result))
        }
        Err(e) => {
            tracing::error!("Failed to scrape url={} error={}", req.url, e);
            Err((StatusCode::INTERNAL_SERVER_ERROR, e))
        }
    }
}
