//! On-device dyld shared cache image index (IDA-like DSC Index, no extract).
use anyhow::{bail, Context, Result};
use clap::{Parser, Subcommand};
use std::fs::File;
use std::io::Read;
use std::path::{Path, PathBuf};

const CACHE_CANDIDATES: &[&str] = &[
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
    "/System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e",
    "/System/Library/dyld/dyld_shared_cache_arm64e",
    "/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64",
    "/System/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_x86_64",
    "/System/Library/dyld/dyld_shared_cache_x86_64",
];

const IMAGES_OFFSET_OFF: usize = 0x1C0;
const IMAGES_OFFSET_OLD_OFF: usize = 0x18;

#[derive(Parser)]
#[command(name = "ghidra-vibe-dsc-index")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Locate on-device dyld shared cache
    #[command(name = "find-cache", alias = "find")]
    FindCache,
    List {
        #[arg(long)]
        cache: Option<PathBuf>,
        #[arg(long, short = 'q')]
        query: Option<String>,
        #[arg(long, default_value_t = 0)]
        limit: usize,
    },
    Resolve {
        #[arg(long)]
        image: Option<String>,
        #[arg(long, short = 'q')]
        query: Option<String>,
        #[arg(long)]
        cache: Option<PathBuf>,
    },
}

fn find_cache() -> Result<PathBuf> {
    for c in CACHE_CANDIDATES {
        let p = PathBuf::from(c);
        if p.is_file() {
            return Ok(p);
        }
    }
    bail!("No on-device dyld shared cache found");
}

fn read_cstring(data: &[u8], off: usize) -> String {
    if off >= data.len() {
        return String::new();
    }
    let end = data[off..]
        .iter()
        .position(|&b| b == 0)
        .map(|i| off + i)
        .unwrap_or_else(|| (off + 1024).min(data.len()));
    String::from_utf8_lossy(&data[off..end]).into_owned()
}

fn list_from_header(cache: &Path) -> Result<Vec<(u64, String)>> {
    let max_bytes: usize = std::env::var("GHIDRA_VIBE_DSC_INDEX_BYTES")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(8 * 1024 * 1024);
    let mut fh = File::open(cache).with_context(|| format!("open {}", cache.display()))?;
    let mut data = vec![0u8; max_bytes];
    let n = fh.read(&mut data)?;
    data.truncate(n);
    if !data.starts_with(b"dyld_v1") {
        bail!("Not a dyld shared cache: {}", cache.display());
    }
    let mut images_offset =
        u32::from_le_bytes(data[IMAGES_OFFSET_OFF..IMAGES_OFFSET_OFF + 4].try_into()?);
    let mut images_count =
        u32::from_le_bytes(data[IMAGES_OFFSET_OFF + 4..IMAGES_OFFSET_OFF + 8].try_into()?);
    if images_offset == 0 || images_count == 0 {
        images_offset =
            u32::from_le_bytes(data[IMAGES_OFFSET_OLD_OFF..IMAGES_OFFSET_OLD_OFF + 4].try_into()?);
        images_count = u32::from_le_bytes(
            data[IMAGES_OFFSET_OLD_OFF + 4..IMAGES_OFFSET_OLD_OFF + 8].try_into()?,
        );
    }
    if images_offset == 0 || images_count == 0 {
        bail!("Could not locate images table in cache header");
    }
    let mut out = Vec::new();
    for i in 0..images_count {
        let off = images_offset as usize + i as usize * 32;
        if off + 32 > data.len() {
            break;
        }
        let address = u64::from_le_bytes(data[off..off + 8].try_into()?);
        let path_off = u32::from_le_bytes(data[off + 24..off + 28].try_into()?) as usize;
        let path = read_cstring(&data, path_off);
        if !path.is_empty() {
            out.push((address, path));
        }
    }
    if out.is_empty() {
        bail!("Parsed zero image paths from header");
    }
    Ok(out)
}

fn list_from_map(cache: &Path) -> Result<Vec<(u64, String)>> {
    let map_path = {
        let p = PathBuf::from(format!("{}.map", cache.display()));
        if p.is_file() {
            p
        } else {
            cache.with_extension("map")
        }
    };
    let text = std::fs::read_to_string(&map_path)
        .with_context(|| format!("map {}", map_path.display()))?;
    let mut out = Vec::new();
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('/') {
            out.push((0u64, line.to_string()));
        }
    }
    if out.is_empty() {
        bail!("Empty map file");
    }
    Ok(out)
}

fn list_images(cache: &Path) -> Result<Vec<(u64, String)>> {
    list_from_header(cache).or_else(|_| list_from_map(cache))
}

fn resolve_image(query: &str, cache: &Path) -> Result<String> {
    let q = query.trim();
    let imgs = list_images(cache)?;
    if q.starts_with('/') && imgs.iter().any(|(_, p)| p == q) {
        return Ok(q.to_string());
    }
    let aliases = [
        (
            "appkit",
            "/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit",
        ),
        (
            "skylight",
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight",
        ),
    ];
    let key = q.to_lowercase().trim_end_matches(".framework").to_string();
    for (alias, want) in aliases {
        if key == alias {
            if let Some((_, p)) = imgs.iter().find(|(_, p)| p == want) {
                return Ok(p.clone());
            }
            return Ok(want.to_string());
        }
    }
    let ql = q.to_lowercase();
    let mut matches: Vec<String> = imgs
        .into_iter()
        .map(|(_, p)| p)
        .filter(|p| p.to_lowercase().contains(&ql))
        .collect();
    if matches.is_empty() {
        bail!("No DSC image matching {query:?}");
    }
    matches.sort_by_key(|p| {
        let exact = if p.trim_end_matches('/').ends_with(&format!("/{q}")) {
            0
        } else {
            1
        };
        (exact, p.len())
    });
    Ok(matches.remove(0))
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::FindCache => {
            println!("{}", find_cache()?.display());
        }
        Cmd::List {
            cache,
            query,
            limit,
        } => {
            let cache = cache.map(Ok).unwrap_or_else(find_cache)?;
            let mut imgs = list_images(&cache)?;
            if let Some(q) = query {
                let ql = q.to_lowercase();
                imgs.retain(|(_, p)| p.to_lowercase().contains(&ql));
            }
            if limit > 0 {
                imgs.truncate(limit);
            }
            for (_, path) in imgs {
                println!("{path}");
            }
        }
        Cmd::Resolve { image, query, cache } => {
            let cache = cache.map(Ok).unwrap_or_else(find_cache)?;
            let img = image.or(query).ok_or_else(|| anyhow::anyhow!("--image required"))?;
            println!("{}", resolve_image(&img, &cache)?);
        }
    }
    Ok(())
}
