use regex::Regex;
use scraper::{ElementRef, Html, Selector};
use std::collections::HashSet;
use crate::domain::{
    error::ScrapingError,
    models::{Link, ScrapeResponse},
    ports::HtmlParserPort,
};

const MAX_LINKS: usize = 20;
const MAX_SECTIONS: usize = 10;

const CONTENT_SELECTORS: &[&str] = &[
    "#guide_content",
    ".guide_content",
    ".workshop_item_body",
    ".rightDetailsBlock",
    "article",
    "main",
    "[role=main]",
    ".post-content",
    ".entry-content",
    ".content",
    "#content",
    ".post-body",
];

pub struct ScraperParser;

impl HtmlParserPort for ScraperParser {
    fn parse(&self, html: &str) -> Result<ScrapeResponse, ScrapingError> {
        let document = Html::parse_document(html);
        let title = Self::extract_title(&document);
        let sections = Self::extract_sections(&document);
        let links = Self::extract_links(&document);
        let text = Self::extract_from_container(&document)
            .unwrap_or_else(|| Self::extract_body_text(&document));
        Ok(ScrapeResponse { title, sections, links, text })
    }
}

impl ScraperParser {
    fn extract_title(document: &Html) -> String {
        let h1_sel = Selector::parse("h1").unwrap();
        if let Some(h1) = document.select(&h1_sel).next() {
            let t = h1.text().collect::<String>();
            let trimmed = t.trim();
            if !trimmed.is_empty() {
                return trimmed.to_string();
            }
        }
        let title_sel = Selector::parse("title").unwrap();
        document
            .select(&title_sel)
            .next()
            .map(|el| el.text().collect::<String>().trim().to_string())
            .unwrap_or_default()
    }

    fn extract_sections(document: &Html) -> Vec<String> {
        let h2_sel = Selector::parse("h2").unwrap();
        let h3_sel = Selector::parse("h3").unwrap();
        let mut sections = Vec::new();
        for heading in document.select(&h2_sel).chain(document.select(&h3_sel)) {
            let text = heading.text().collect::<String>().trim().to_string();
            if !text.is_empty() && sections.len() < MAX_SECTIONS {
                sections.push(text);
            }
        }
        sections
    }

    fn extract_links(document: &Html) -> Vec<Link> {
        let a_sel = Selector::parse("a[href]").unwrap();
        let mut seen = HashSet::new();
        let mut links = Vec::new();
        for el in document.select(&a_sel) {
            if links.len() >= MAX_LINKS {
                break;
            }
            if let Some(href) = el.value().attr("href") {
                let href = href.trim();
                let text = el.text().collect::<String>().trim().to_string();
                if !href.is_empty() && href != "#" && !text.is_empty() && seen.insert(href.to_string()) {
                    links.push(Link { href: href.to_string(), text });
                }
            }
        }
        links
    }

    fn extract_body_text(document: &Html) -> String {
        let body_sel = Selector::parse("body").unwrap();
        let text = document
            .select(&body_sel)
            .next()
            .map(|el| el.text().collect::<Vec<_>>().join(" "))
            .unwrap_or_default();
        let re = Regex::new(r"\s+").unwrap();
        re.replace_all(&text, " ").trim().to_string()
    }

    fn extract_from_container(document: &Html) -> Option<String> {
        for sel_str in CONTENT_SELECTORS {
            if let Ok(sel) = Selector::parse(sel_str) {
                if let Some(el) = document.select(&sel).next() {
                    let text = Self::collect_text(el);
                    if text.len() > 200 {
                        return Some(text);
                    }
                }
            }
        }
        None
    }

    fn collect_text(el: ElementRef) -> String {
        let text = el.text().collect::<Vec<_>>().join(" ");
        let re = Regex::new(r"\s+").unwrap();
        re.replace_all(&text, " ").trim().to_string()
    }
}
