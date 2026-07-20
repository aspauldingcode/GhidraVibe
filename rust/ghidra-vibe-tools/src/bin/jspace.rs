use anyhow::Result;
use clap::{Parser, Subcommand};
use ghidra_vibe_tools::index_mcp::{index_from_mcp, index_playbook_only};
use ghidra_vibe_tools::retrieve::{discovery_context, search};
use ghidra_vibe_tools::JSpaceStore;
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "ghidra-vibe-jspace", about = "JSpace RE RAG (Rust)")]
struct Cli {
    #[command(subcommand)]
    cmd: Cmd,
}

#[derive(Subcommand)]
enum Cmd {
    /// Seed RE playbook cards
    Init {
        #[arg(long, env = "GHIDRA_VIBE_JSPACE_DB")]
        db: Option<PathBuf>,
    },
    /// Index from live Ghidra MCP
    Index {
        #[arg(long, env = "GHIDRA_VIBE_JSPACE_DB")]
        db: Option<PathBuf>,
        #[arg(long, default_value_t = 200)]
        limit: usize,
        #[arg(long = "decompile-top", default_value_t = 40)]
        decompile_top: usize,
        #[arg(long)]
        playbook_only: bool,
        #[arg(long, default_value = "")]
        program: String,
    },
    /// Hybrid FTS+vector search
    Search {
        query: String,
        #[arg(long, env = "GHIDRA_VIBE_JSPACE_DB")]
        db: Option<PathBuf>,
        #[arg(long, default_value_t = 8)]
        top: usize,
        #[arg(long)]
        kind: Option<String>,
    },
    /// Discovery context pack for the agent
    Discover {
        query: String,
        #[arg(long, env = "GHIDRA_VIBE_JSPACE_DB")]
        db: Option<PathBuf>,
        #[arg(long, default_value_t = 8)]
        top: usize,
        #[arg(long)]
        function: Option<String>,
        #[arg(long = "decompile-file")]
        decompile_file: Option<PathBuf>,
    },
    Stats {
        #[arg(long, env = "GHIDRA_VIBE_JSPACE_DB")]
        db: Option<PathBuf>,
    },
}

fn default_db() -> PathBuf {
    if let Ok(p) = std::env::var("GHIDRA_VIBE_JSPACE_DB") {
        return PathBuf::from(p);
    }
    let cwd = std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."));
    cwd.join(".ghidra-vibe-jspace").join("jspace.sqlite")
}

fn resolve_db(db: Option<PathBuf>) -> PathBuf {
    db.unwrap_or_else(default_db)
}

fn main() -> Result<()> {
    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Init { db } => {
            let store = JSpaceStore::open(resolve_db(db))?;
            println!("{}", serde_json::to_string_pretty(&index_playbook_only(&store)?)?);
        }
        Cmd::Index {
            db,
            limit,
            decompile_top,
            playbook_only,
            program,
        } => {
            let store = JSpaceStore::open(resolve_db(db))?;
            let out = if playbook_only {
                index_playbook_only(&store)?
            } else {
                index_from_mcp(&store, &program, limit, decompile_top)?
            };
            println!("{}", serde_json::to_string_pretty(&out)?);
        }
        Cmd::Search {
            query,
            db,
            top,
            kind,
        } => {
            let store = JSpaceStore::open(resolve_db(db))?;
            let hits = search(&store, &query, top, kind.as_deref())?;
            println!("{}", serde_json::to_string_pretty(&hits)?);
        }
        Cmd::Discover {
            query,
            db,
            top,
            function,
            decompile_file,
        } => {
            let store = JSpaceStore::open(resolve_db(db))?;
            let dec = decompile_file
                .filter(|p| p.is_file())
                .and_then(|p| std::fs::read_to_string(p).ok());
            let pack = discovery_context(
                &store,
                &query,
                top,
                function.as_deref(),
                dec.as_deref(),
            )?;
            println!("{pack}");
        }
        Cmd::Stats { db } => {
            let store = JSpaceStore::open(resolve_db(db))?;
            println!("{}", serde_json::to_string_pretty(&store.stats()?)?);
        }
    }
    Ok(())
}
