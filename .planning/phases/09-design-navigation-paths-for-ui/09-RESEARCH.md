# Phase 9: Design Navigation Paths for UI - Research

**Researched:** 2026-03-09
**Domain:** MCP Apps protocol, conversational image search UX, ChatGPT widget interactions
**Confidence:** MEDIUM (protocol is new, some areas have limited documentation)

## Summary

MCP Apps is an official MCP extension (spec finalized January 26, 2026) that allows tools to return interactive HTML interfaces rendered in sandboxed iframes within the conversation. Widgets are custom HTML/JS/CSS pages -- not predefined widget types. There is no built-in "tree widget" or "grid widget"; developers build whatever UI they need as standard web pages. Widgets communicate with the host via JSON-RPC over postMessage, and can trigger tool calls (`tools/call`) and send follow-up messages (`ui/message`) back to the conversation.

The critical constraint for this design phase: **cross-widget communication does not exist**. Each widget is an isolated iframe. One widget cannot update another widget. The MCP Apps specification explicitly lists "widget communication: multiple widgets talking to each other" as a **future enhancement, not current capability**. This means refinement interactions must happen within a single widget (intra-widget state) or by generating a new conversation turn with an entirely new widget.

**Primary recommendation:** Design each tool response as a self-contained interactive widget that handles its own drill-down, filtering, and navigation internally. Use `tools/call` from within the widget for data refreshes, and `ui/message` for actions that should produce a new conversational turn (e.g., "show me more like this").

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Dual entry points: free-form NL + MCP prompts (e.g., `/find_images dogs`)
- Two operational modes: Tool mode (focused MCP tools) and Code mode (SQL generation)
- Use-case oriented tools: find_images, query), narrow_results(filter), get_image_details(id), explore_category(class)
- Each tool may query multiple SQL views internally
- Tools return StructuredOutput (JSON per OutputSchema rendered as widget HTML) plus unstructured context text for LLM conversation
- Visual-first interaction: image thumbnails as primary navigation mechanism
- Refinement: both clickable facets AND free-text follow-ups accepted
- Image detail view with annotations overlay and navigate-from-image actions
- Code mode loads 00-mcp-reference.sql as context resource

### Claude's Discretion
- Exact number and granularity of MCP tools
- Internal SQL query composition within tools
- Error handling and edge case responses
- Widget HTML/CSS styling details

### Deferred Ideas (OUT OF SCOPE)
None -- discussion stayed within phase scope.
</user_constraints>

## Answers to Open Research Questions

### Q1: Cross-Widget Interaction (Can clicking one widget update another?)

**Answer: No. Not currently supported.** Confidence: HIGH

Each MCP Apps widget runs in its own sandboxed iframe. There is no mechanism for one widget to communicate with or update another widget. The official MCP Apps blog post (fka.dev, November 2025) explicitly states: "Future enhancements might include...Widget communication: Multiple widgets talking to each other." This is listed as a future capability, not a current one.

**What IS supported:**
- **Intra-widget interactivity**: A widget can call `tools/call` to fetch new data and re-render itself without a new conversation turn. Example: clicking a facet in a results grid widget calls `narrow_results` and the widget re-renders with filtered results.
- **New conversation turn**: A widget can call `ui/message` to inject a follow-up message into the conversation (as if the user typed it). This triggers the LLM to reason and potentially call another tool, which produces a NEW widget below in the conversation. The old widget remains frozen.

**Design implication:** Refinement facets must be WITHIN the results grid widget, not in a separate sidebar widget. The widget itself manages filter state and data refresh via `tools/call`.

**Sources:**
- [fka.dev MCP Apps 101](https://blog.fka.dev/blog/2025-11-22-mcp-apps-101-bringing-interactive-uis-to-ai-conversations/) -- explicitly lists cross-widget as future
- [MCP Apps official docs](https://modelcontextprotocol.io/docs/extensions/apps) -- no mention of cross-widget communication
- [OpenAI community thread](https://community.openai.com/t/trigger-new-tool-widgets-with-sendfollowupmessage/1367100) -- confirms `sendFollowUpMessage` creates new turn, does not update existing widget

### Q2: Hierarchy Tree Widget (Does MCP Apps have built-in tree/hierarchy widgets?)

**Answer: No built-in widget types. You build your own.** Confidence: HIGH

MCP Apps does NOT provide a library of predefined widget types (tree, list, grid, etc.). Widgets are custom HTML pages rendered in iframes. You write whatever HTML/CSS/JS you want -- a collapsible tree, breadcrumb trail, flat list, or anything else. The framework provides the communication bridge; the UI is entirely up to the developer.

**What this means for hierarchy browsing:**
- A collapsible tree IS possible -- you build it as a standard HTML/JS component
- A breadcrumb trail IS possible -- same approach
- The hierarchy data (602 classes, 5 depth levels, root_path like "Entity > Animal > Carnivore > Dog") maps naturally to both tree and breadcrumb patterns
- The `explore_category` tool can return hierarchy data that the widget renders as an expandable tree with click-to-drill behavior
- Clicking a tree node can trigger `tools/call` for the subtree, re-rendering the widget in place

**Design implication:** Design the hierarchy widget as a custom component. Recommend a collapsible tree with breadcrumb trail at the top (showing current path). Clicking a leaf category triggers `tools/call` to fetch images for that class, and the widget transitions from tree-view to grid-view within the same iframe.

**Sources:**
- [OpenAI Build ChatGPT UI](https://developers.openai.com/apps-sdk/build/chatgpt-ui/) -- examples are all custom components (Pizzaz List, Carousel, Map, Album, Video)
- [MCP Apps official docs](https://modelcontextprotocol.io/docs/extensions/apps) -- "interactive HTML interfaces" with no predefined types
- [ext-apps examples](https://github.com/modelcontextprotocol/ext-apps) -- all custom HTML/JS

### Q3: Widget-to-Tool Triggering (Can clicking a widget element trigger a tool call?)

**Answer: Yes. Two mechanisms available.** Confidence: HIGH

**Mechanism 1: `tools/call` (silent, intra-widget)**
The widget calls a tool directly via the bridge. The result comes back to the widget (not the conversation). The widget re-renders with new data. The user sees an instant UI update. The LLM is NOT involved.

```javascript
// Widget calls tool directly
const result = await app.callServerTool({
  name: "narrow_results",
  arguments: { filter: "breed:poodle" }
});
// Widget re-renders with result.structuredContent
render(result.structuredContent);
```

**Mechanism 2: `ui/message` (conversational, new turn)**
The widget posts a message to the conversation as if the user typed it. The LLM processes the message, potentially calls another tool, and produces a new response (potentially with a new widget) below in the conversation.

```javascript
// Widget sends follow-up message to conversation
window.parent.postMessage({
  jsonrpc: "2.0",
  method: "ui/message",
  params: {
    role: "user",
    content: [{ type: "text", text: "Show me more poodle images" }]
  }
}, "*");
```

**Mechanism 3: `ui/update-model-context` (silent, context only)**
The widget updates the model's context without generating a new turn. Useful for syncing UI state so the model knows what the user is looking at.

**Design implication:** Use `tools/call` for fast, within-widget interactions (facet clicks, pagination, sort changes). Use `ui/message` for actions that should produce a new conversational response (navigate-from-image, "show me more like this"). Use `ui/update-model-context` to keep the LLM aware of what the user is currently viewing.

**Important caveat:** `sendFollowUpMessage` / `ui/message` reliability is reported as inconsistent in community forums. Sometimes ChatGPT responds with text instead of triggering the expected tool call. Design should not rely solely on `ui/message` for critical navigation paths -- always provide a text-based fallback.

**Sources:**
- [OpenAI Build ChatGPT UI](https://developers.openai.com/apps-sdk/build/chatgpt-ui/) -- `tools/call` example with dice re-roll
- [OpenAI Build MCP Server](https://developers.openai.com/apps-sdk/build/mcp-server/) -- `_meta.ui.visibility` and `callServerTool`
- [OpenAI community](https://community.openai.com/t/trigger-new-tool-widgets-with-sendfollowupmessage/1367100) -- reliability issues with `sendFollowUpMessage`

## Standard Stack

### Core (Design Phase -- specification only, no implementation)
| Component | Version/Spec | Purpose | Why Standard |
|-----------|-------------|---------|--------------|
| MCP Apps Extension | 2026-01-26 spec | Interactive widget protocol | Official MCP extension, supported by ChatGPT, Claude, VS Code, Goose |
| `@modelcontextprotocol/ext-apps` | Latest | App SDK (convenience wrapper) | Official SDK from MCP project |
| JSON-RPC 2.0 over postMessage | N/A | Widget-host communication | MCP Apps bridge protocol |

### Supporting (for design reference)
| Component | Purpose | When Referenced |
|-----------|---------|----------------|
| React/Preact/Vanilla JS | Widget implementation framework | When specifying widget templates |
| OpenAI Apps SDK | ChatGPT-specific extensions | For ChatGPT-specific features like `window.openai` |

### Host Compatibility
| Host | MCP Apps Support | Notes |
|------|-----------------|-------|
| ChatGPT | Yes | Primary target, fullest feature set |
| Claude Desktop | Yes | Supported |
| VS Code Copilot | Yes | Supported |
| Goose | Yes | Supported |

## Architecture Patterns

### Recommended Design Document Structure
```
design/
  navigation-flows/
    01-search-flow.md          # find_images conversation flow
    02-refinement-flow.md      # narrow_results interaction
    03-detail-flow.md          # get_image_details view
    04-hierarchy-flow.md       # explore_category navigation
  tool-definitions/
    tools.json                 # MCP tool schemas (input/output)
  widget-specs/
    results-grid.md            # Image grid widget specification
    image-detail.md            # Single image detail widget spec
    hierarchy-browser.md       # Category tree widget spec
  patterns/
    interaction-model.md       # tools/call vs ui/message decision tree
```

### Pattern 1: Self-Contained Interactive Widget
**What:** Each tool response produces a single widget that handles its own state, filtering, and data refresh internally via `tools/call`.
**When to use:** Always. Cross-widget communication is not available.
**Key principle:** The widget IS the application. It contains the grid, the facets, the pagination, and the detail overlay all in one iframe.

### Pattern 2: Decoupled Data + Render Tools
**What:** Separate data-fetching tools (model-visible) from render tools (model-visible, declare `_meta.ui.resourceUri`). The model fetches data first, then decides which UI to show.
**When to use:** When the same data might be rendered differently depending on context.
**Source:** [OpenAI Build ChatGPT UI docs](https://developers.openai.com/apps-sdk/build/chatgpt-ui/)

### Pattern 3: Progressive Disclosure via Conversation Turns
**What:** Each conversation turn reveals more detail. Broad query -> results grid -> click image -> detail view (new turn). Each turn is a new widget.
**When to use:** For the main search-to-detail flow.
**Key insight:** The conversation itself IS the progressive disclosure mechanism. Earlier widgets remain visible above as context.

### Pattern 4: Intra-Widget Drill-Down
**What:** Widget handles its own drill-down. Clicking a facet calls `tools/call` and the widget re-renders. No new conversation turn needed.
**When to use:** For fast filtering (facets, sort, pagination) that shouldn't clutter the conversation.

### Anti-Patterns to Avoid
- **Multi-widget layouts:** Do NOT design side-by-side widgets (e.g., hierarchy tree left, results right). Each tool call produces one widget. Use intra-widget layout instead.
- **Relying solely on `ui/message` for navigation:** Unreliable. Always design so `tools/call` handles the primary path within the widget, with `ui/message` as a supplementary path for new-context actions.
- **Overly complex single widgets:** A widget trying to do everything (search + filter + detail + hierarchy + relationships) becomes unusable. Keep widgets focused; use conversation turns for major context switches.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Widget-host communication | Custom postMessage protocol | `@modelcontextprotocol/ext-apps` App class | Handles JSON-RPC, timeouts, message routing |
| Image thumbnail grid | Complex custom CSS grid | CSS Grid with `thumbnail_300k_url` | Standard web layout; images are just URLs |
| Hierarchy tree rendering | Custom tree data structure | Recursive component consuming `class_hierarchy` view's `root_path` | `root_path` already provides "Entity > Animal > Dog" strings |
| Tool schema validation | Custom input validation | JSON Schema (MCP standard) | MCP tools use JSON Schema for inputSchema/outputSchema |

## Common Pitfalls

### Pitfall 1: Assuming Cross-Widget Communication Exists
**What goes wrong:** Designing a layout with a sidebar facet widget that updates a separate results grid widget.
**Why it happens:** Natural assumption from web app experience. MCP Apps are NOT a single-page application.
**How to avoid:** Every interactive surface must live within a single widget. Facets and results share one iframe.
**Warning signs:** Design spec references "sidebar widget" or "updating the other panel."

### Pitfall 2: Overusing ui/message for Navigation
**What goes wrong:** Widget clicks rely on `ui/message` to trigger tool calls. ChatGPT sometimes responds with text instead of calling the tool.
**Why it happens:** `ui/message` goes through the LLM, which decides what to do. It might not call the tool you expect.
**How to avoid:** Use `tools/call` for predictable intra-widget interactions. Reserve `ui/message` for truly conversational actions where LLM reasoning is desired.
**Warning signs:** Design spec has click actions that say "sends message to trigger find_images."

### Pitfall 3: Widget Context Loss
**What goes wrong:** Dynamic widget data (from MCP tool results) doesn't reach the widget iframe properly.
**Why it happens:** Documented community issue -- `structuredContent` passing to widgets has rough edges.
**How to avoid:** Design tool responses with clear `structuredContent` (model-readable summary), `content` (conversation text), and `_meta` (widget-exclusive data). Keep `_meta` lean.
**Warning signs:** Widget needs large payloads or complex nested state from tool results.
**Source:** [OpenAI community thread on dynamic widgets](https://community.openai.com/t/chatgpt-dynamic-widgets-for-mcp-responses/1370612)

### Pitfall 4: Designing for Desktop Web App Paradigm
**What goes wrong:** Spec describes URL routing, browser back buttons, persistent global state.
**Why it happens:** Thinking of the widget as a single-page application rather than a conversational component.
**How to avoid:** Each widget is ephemeral. State persists only within the current widget's lifetime. Conversation history provides the "back button." Design for conversation-native patterns.

### Pitfall 5: Ignoring the "is" Relationship Dominance
**What goes wrong:** Relationship browsing UI shows 81.8% "is" relationships drowning out meaningful spatial/action relationships.
**Why it happens:** Not filtering the dominant "is" type from relationship displays.
**How to avoid:** Default relationship views should filter to action/spatial relationships (`WHERE relationship_label != 'is'`). Provide explicit toggle to include attribute relationships.

## Code Examples

### MCP Tool Definition with Widget Reference
```typescript
// Source: OpenAI Apps SDK docs + MCP Apps spec
{
  name: "find_images",
  description: "Search for images matching a query. Returns a visual grid of matching thumbnails with facets for refinement.",
  inputSchema: {
    type: "object",
    properties: {
      query: { type: "string", description: "Natural language search query or class name" },
      limit: { type: "number", default: 20 },
      relationship: { type: "string", description: "Optional relationship filter" }
    },
    required: ["query"]
  },
  _meta: {
    ui: {
      resourceUri: "ui://widgets/results-grid.html"
    }
  }
}
```

### Widget Calling Tool for In-Place Refresh
```javascript
// Source: OpenAI Build ChatGPT UI docs
// Inside results-grid widget: user clicks a facet
async function onFacetClick(facetValue) {
  const result = await app.callServerTool({
    name: "narrow_results",
    arguments: { filter: facetValue, previous_query: currentQuery }
  });
  if (result?.structuredContent) {
    renderGrid(result.structuredContent);
  }
}
```

### Widget Sending Follow-Up Message for New Context
```javascript
// Source: OpenAI Build ChatGPT UI docs
// Inside results-grid widget: user clicks "show me more like this"
function onShowMoreLikeThis(imageId) {
  window.parent.postMessage({
    jsonrpc: "2.0",
    method: "ui/message",
    params: {
      role: "user",
      content: [{
        type: "text",
        text: `Show me more images similar to ${imageId}`
      }]
    }
  }, "*");
}
```

### Tool Response Structure (Three-Layer Pattern)
```json
{
  "structuredContent": {
    "query": "dogs",
    "total_results": 523,
    "page": 1,
    "facets": {
      "breeds": ["Poodle", "German shepherd", "Labrador"],
      "relationships": ["on", "wears", "holds"]
    },
    "summary": "523 dog images found across 12 breeds"
  },
  "content": [
    {
      "type": "text",
      "text": "Found 523 images of dogs. The most common breeds are Poodle (89), German Shepherd (67), and Labrador (54). You can narrow by breed, relationship type, or describe what you're looking for."
    }
  ],
  "_meta": {
    "images": [
      { "id": "000a1249af2bc5f0", "thumbnail": "https://...", "labels": ["Dog", "Poodle"], "confidence": 0.95 }
    ],
    "hierarchy_context": {
      "path": "Entity > Animal > Carnivore > Dog",
      "children": ["Poodle", "German shepherd", "Labrador", "..."]
    }
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Text-only MCP tool responses | MCP Apps interactive widgets | Jan 2026 (spec finalized) | Tools can now return full interactive UIs |
| ChatGPT Plugins (deprecated) | ChatGPT Apps via MCP Apps | Oct 2025 (Apps launch) | Standardized protocol replacing proprietary plugin system |
| Proprietary widget APIs | Open MCP Apps standard | Jan 2026 | Same widget code works across ChatGPT, Claude, VS Code, Goose |
| Client-specific UI code | Framework-agnostic HTML/JS | Jan 2026 | Build once, render anywhere |

**Deprecated/outdated:**
- ChatGPT Plugins: replaced by ChatGPT Apps / MCP Apps
- Custom `window.openai` patterns: prefer MCP Apps standard bridge for portability

## Open Questions

1. **`ui/message` reliability for tool triggering**
   - What we know: Community reports that `sendFollowUpMessage` sometimes produces text responses instead of tool calls
   - What's unclear: Whether this is a ChatGPT-specific issue, a prompt engineering problem, or a fundamental limitation
   - Recommendation: Design primary navigation via `tools/call` (reliable). Use `ui/message` only for supplementary "ask the LLM" actions. Always provide text-input fallback.

2. **Widget payload size limits**
   - What we know: `_meta` carries widget-exclusive data. `structuredContent` is model-visible.
   - What's unclear: Maximum payload size for `_meta`. With 20+ image thumbnails per page, the JSON could be substantial.
   - Recommendation: Design pagination into the widget. Fetch images in batches of 12-20 via `tools/call`. Keep initial tool response lean.

3. **`tools/call` visibility control**
   - What we know: `_meta.ui.visibility: ["model", "app"]` controls whether model, widget, or both can call a tool.
   - What's unclear: Exact behavior when widget calls a model-only tool, or vice versa.
   - Recommendation: Design some tools as `["app"]` only (widget-internal data fetching) and others as `["model", "app"]` (both LLM and widget can invoke).

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | Manual design review (this is a design-only phase) |
| Config file | N/A |
| Quick run command | N/A (design documents, not code) |
| Full suite command | N/A |

### Phase Requirements to Test Map
| Req ID | Behavior | Test Type | Validation Method | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| N/A | Conversation flows are complete and cover all entry points | manual-only | Review design docs for dual entry point coverage | N/A |
| N/A | Tool definitions have valid inputSchema/outputSchema | manual-only | Validate JSON Schema syntax in tool specs | N/A |
| N/A | Widget specs account for no cross-widget communication | manual-only | Audit widget specs for cross-widget assumptions | N/A |
| N/A | All 8 example query patterns map to conversation flows | manual-only | Cross-reference queries/examples/ with flow docs | N/A |
| N/A | Hierarchy navigation covers 5 depth levels | manual-only | Trace hierarchy flow through all levels | N/A |

**Justification for manual-only:** This phase produces design documents, not executable code. Validation is through design review, not automated tests.

### Sampling Rate
- **Per task:** Review design document for internal consistency
- **Per wave:** Cross-reference all design documents for completeness
- **Phase gate:** All conversation flows traced, all tools defined, all widget specs complete

### Wave 0 Gaps
None -- design phase does not require test infrastructure.

## Sources

### Primary (HIGH confidence)
- [MCP Apps official docs](https://modelcontextprotocol.io/docs/extensions/apps) -- architecture, security model, host support
- [OpenAI Build ChatGPT UI](https://developers.openai.com/apps-sdk/build/chatgpt-ui/) -- widget rendering, bridge API, code examples
- [OpenAI Build MCP Server](https://developers.openai.com/apps-sdk/build/mcp-server/) -- tool registration, outputSchema, visibility control
- [MCP Apps compatibility in ChatGPT](https://developers.openai.com/apps-sdk/mcp-apps-in-chatgpt/) -- ChatGPT-specific compatibility
- [MCP Tools specification](https://modelcontextprotocol.io/specification/2025-06-18/server/tools) -- outputSchema, structured content

### Secondary (MEDIUM confidence)
- [MCP Apps 101 - fka.dev](https://blog.fka.dev/blog/2025-11-22-mcp-apps-101-bringing-interactive-uis-to-ai-conversations/) -- cross-widget limitation confirmed, bridge API details
- [MCP Apps blog Jan 2026](http://blog.modelcontextprotocol.io/posts/2026-01-26-mcp-apps/) -- latest spec updates, client support matrix
- [Shopify MCP UI blog](https://shopify.engineering/mcp-ui-breaking-the-text-wall) -- industry adoption patterns

### Tertiary (LOW confidence)
- [OpenAI community: sendFollowUpMessage](https://community.openai.com/t/trigger-new-tool-widgets-with-sendfollowupmessage/1367100) -- reliability issues (anecdotal, community reports)
- [OpenAI community: dynamic widgets](https://community.openai.com/t/chatgpt-dynamic-widgets-for-mcp-responses/1370612) -- context passing issues (unresolved)

## Metadata

**Confidence breakdown:**
- MCP Apps architecture: HIGH -- official docs, spec, multiple sources agree
- Cross-widget limitation: HIGH -- explicitly confirmed in spec blog post as future feature
- Widget-to-tool triggering: HIGH -- code examples from official docs
- `ui/message` reliability: LOW -- only community forum reports, no official acknowledgment
- Design patterns: MEDIUM -- extrapolated from architecture constraints and examples

**Research date:** 2026-03-09
**Valid until:** 2026-04-09 (MCP Apps spec is new and evolving; monitor for updates)
