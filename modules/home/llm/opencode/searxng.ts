// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//                                          // opencode // searxng web_search
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
//
// A legible `web_search` tool backed by the self-hosted SearXNG instance on the
// tailnet (privacy-maxed, unauthed JSON API, no logging). Gives junior agents a
// small, obvious tool surface instead of asking them to hand-roll curl+jq.
//
// Endpoint resolution (first that is set wins):
//   1. the `baseUrl` plugin option  (["./plugin/searxng.ts", { baseUrl: "..." }])
//   2. $SEARXNG_URL
//   3. the fleet default below (reachable on the tailnet, firewall-scoped to
//      tailscale0 — not the public internet)
//
// Config is loaded once at startup; after editing this file, restart opencode.

import type { Plugin } from "@opencode-ai/plugin"
import { tool } from "@opencode-ai/plugin"

const DEFAULT_BASE_URL = "http://ultraviolence.osiris-walleye.ts.net:8889"

type SearxResult = {
  title?: string
  url?: string
  content?: string
  engine?: string
  score?: number
  publishedDate?: string | null
}

const CATEGORIES = ["general", "news", "it", "science", "images", "videos", "map", "music", "files"] as const
const TIME_RANGES = ["", "day", "week", "month", "year"] as const

export default (async ({ $ }, options) => {
  const baseUrl = String(
    (options?.baseUrl as string | undefined) ?? process.env.SEARXNG_URL ?? DEFAULT_BASE_URL,
  ).replace(/\/+$/, "")

  return {
    tool: {
      web_search: tool({
        description: [
          "Search the live web via the self-hosted SearXNG metasearch engine and return",
          "ranked results (title, URL, snippet). Use this whenever you need current",
          "information, documentation, or to find a page you can then fetch. Results are",
          "aggregated from DuckDuckGo, Brave, Startpage, Wikipedia, GitHub, Hacker News,",
          "and the Arch/NixOS wikis. Private and unlogged.",
        ].join(" "),
        args: {
          query: tool.schema.string().min(1).describe("The search query. Plain words work best; no site: operators needed."),
          count: tool.schema
            .number()
            .int()
            .min(1)
            .max(20)
            .default(8)
            .describe("How many results to return (1-20, default 8)."),
          category: tool.schema
            .enum(CATEGORIES)
            .optional()
            .describe("Optional result category. Omit for a normal 'general' web search."),
          time_range: tool.schema
            .enum(TIME_RANGES)
            .optional()
            .describe("Optional recency filter: day, week, month, or year. Omit for all time."),
          language: tool.schema
            .string()
            .default("en")
            .describe("Language code for results (default 'en')."),
        },
        async execute(args, ctx) {
          const params = new URLSearchParams({
            q: args.query,
            format: "json",
            language: args.language || "en",
          })
          if (args.category) params.set("categories", args.category)
          if (args.time_range) params.set("time_range", args.time_range)

          const url = `${baseUrl}/search?${params.toString()}`

          let res: Response
          try {
            res = await fetch(url, {
              signal: ctx.abort,
              headers: { Accept: "application/json" },
            })
          } catch (e) {
            const msg = e instanceof Error ? e.message : String(e)
            return {
              title: `web_search: unreachable`,
              output: `Could not reach SearXNG at ${baseUrl} (${msg}).\nIs the tailnet up and the service on? Set $SEARXNG_URL or the plugin baseUrl option to override.`,
              metadata: { baseUrl, error: msg },
            }
          }

          if (!res.ok) {
            return {
              title: `web_search: HTTP ${res.status}`,
              output: `SearXNG returned HTTP ${res.status} ${res.statusText} for query ${JSON.stringify(args.query)}.`,
              metadata: { baseUrl, status: res.status },
            }
          }

          const body = (await res.json()) as { results?: SearxResult[] }
          const results = (body.results ?? []).slice(0, args.count)

          if (results.length === 0) {
            return {
              title: `web_search: no results`,
              output: `No results for ${JSON.stringify(args.query)}.`,
              metadata: { baseUrl, query: args.query, count: 0 },
            }
          }

          const formatted = results
            .map((r, i) => {
              const n = i + 1
              const title = r.title?.trim() || "(untitled)"
              const snippet = r.content?.trim().replace(/\s+/g, " ") ?? ""
              const engine = r.engine ? ` · ${r.engine}` : ""
              return [`${n}. ${title}`, `   ${r.url ?? ""}`, snippet ? `   ${snippet}` : ""]
                .filter(Boolean)
                .join("\n")
            })
            .join("\n\n")

          return {
            title: `web_search: ${results.length} result${results.length === 1 ? "" : "s"} for "${args.query}"`,
            output: formatted,
            metadata: {
              baseUrl,
              query: args.query,
              count: results.length,
              urls: results.map((r) => r.url).filter(Boolean),
            },
          }
        },
      }),
    },
  }
}) satisfies Plugin
