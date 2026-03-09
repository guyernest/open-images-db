# Phase 9: Design Navigation Paths for UI - Context

**Gathered:** 2026-03-09
**Status:** Ready for planning

<domain>
## Phase Boundary

Design conversational navigation flows for finding specific images in the Open Images dataset, using ChatGPT Apps with the MCP Apps protocol extension. Produces a design document (multiple files) specifying conversation flows, MCP tool definitions, and UI widget patterns. This is a design phase — no implementation code.

The design uses Open Images as an exemplar but frames patterns that generalize to other media search use cases (CCTV, news, sports clips, entertainment).

</domain>

<decisions>
## Implementation Decisions

### Entry Points (Dual Mode)
- Free-form natural language for power users who know the dataset and what they want
- MCP prompts (e.g., `/find_images dogs`) that trigger structured workflows returning:
  - Initial result set (images matching the query)
  - Hierarchy context (sub-categories/breeds available under the queried class)
  - Navigation options (relationships, co-occurrence patterns)
- The prompt-triggered workflow pre-loads the LLM context with everything needed to guide the user

### Two Operational Modes
- **Tool mode**: Focused MCP tools for common use cases. Tool descriptions + InputSchema/OutputSchema guide the LLM. Tools must be distinct and non-overlapping to avoid LLM confusion across different reasoning levels
- **Code mode**: `/start_code_mode` prompt loads schema resources (like 00-mcp-reference.sql), code generation instructions, positive examples, and common pitfalls. LLM generates SQL/JS on the fly for long-tail queries

### MCP Tool Design
- Use-case oriented tools (not 1:1 view mapping): find_images(query), narrow_results(filter), get_image_details(id), explore_category(class)
- Each tool may query multiple SQL views internally
- Tools return StructuredOutput (JSON per OutputSchema → rendered as widget HTML) plus unstructured context text for the LLM conversation

### Conversation Flow
- Broad/ambiguous queries: return top results immediately + suggest narrowing paths ("Found 500+ images. Focus on a specific animal, relationship, or scene type?")
- Refinement: both clickable facets AND free-text follow-ups accepted
- Visual-first interaction: image thumbnails are the primary navigation mechanism. Users browse visually and refine based on what they see (e.g., "I see poodles and german shepherds, show me more poodles")
- End goal: select and view a single image with full details

### Image Detail View
- Full-size image with annotations overlay (bounding boxes, labels, relationships — toggle-able layers)
- Metadata panel (all labels, confidence scores, relationships, image metadata)
- Navigate-from-image actions ("show me more with this object", "related images", "what else is in this scene?")
- Select/save action (copy URL, download)

### Claude's Discretion
- Exact number and granularity of MCP tools
- Internal SQL query composition within tools
- Error handling and edge case responses
- Widget HTML/CSS styling details

</decisions>

<specifics>
## Specific Ideas

- The `/find_images dogs` workflow should return not just matching images but also the class hierarchy showing available dog breeds, relationships dogs participate in, and co-occurring objects — giving the user a "navigation map" for their search
- Visual browsing is essential: users understand their options by seeing sample images, not reading text lists. "I need a dog image, oh, I see poodles and german shepherds, let's see more poodles"
- Design should feel like the investigative interfaces in crime TV shows / sci-fi movies — conversational, visual, progressively narrowing
- Frame Open Images as one instance of a general media search pattern. The same approach applies to security footage ("yellow car on I-90"), news ("fire report last night"), sports ("Man United goals in last 5 minutes")

</specifics>

<code_context>
## Existing Code Insights

### Reusable Assets
- `00-mcp-reference.sql`: LLM-optimized schema reference — ready for code mode context injection
- 8 example query files (01-08): Cover relationships, hierarchy browsing, entity search, image contents, category exploration — serve as conversation flow templates
- `class_hierarchy` view: Recursive CTE with root_path, depth, display_name — powers hierarchy navigation
- `hierarchy_relationships` view: Ancestor-expanded relationships — enables "Person on Horse" queries that resolve to Man/Woman/Girl/Boy
- `labeled_relationships` view: Human-readable relationship data
- `thumbnail_300k_url` field in images table: Ready for visual display

### Established Patterns
- Views use INNER JOIN with class_descriptions for human-readable names (drops ~3.3% of rows — accepted)
- Hierarchy uses root_path like "Entity > Animal > Carnivore > Dog" for tree navigation
- 27 relationship types, 602 hierarchy classes, 5 depth levels

### Integration Points
- MCP tools will query Athena via the existing views
- StructuredOutput from tools maps to widget HTML per MCP Apps protocol
- Code mode uses existing 00-mcp-reference.sql as context resource

</code_context>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

## Open Research Questions

These emerged during discussion and need investigation before or during planning:

1. **Facet widget interaction**: Can clicking one MCP Apps widget trigger an update in another widget? What cross-widget interaction patterns does the protocol support? This determines whether refinement facets are inline, sidebar, or below-grid.

2. **Hierarchy tree widget**: What widget types does MCP Apps support for tree/hierarchical navigation? Collapsible tree? Breadcrumb trail? Or only flat lists? This determines the hierarchy browsing UX.

3. **Widget-to-tool triggering**: When a user clicks an element in a StructuredOutput widget (e.g., a thumbnail, a category facet), can that click trigger an MCP tool call? Or does interaction require the user to type/select in conversation?

---

*Phase: 09-design-navigation-paths-for-ui*
*Context gathered: 2026-03-09*
