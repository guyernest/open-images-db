# Interaction Model: Widget-Host Communication Patterns

This document defines the decision framework for choosing between MCP Apps interaction mechanisms. Every widget interaction in the Open Images design can be resolved by consulting this document.

## 0. Prompts vs Tools: Server-Orchestrated vs LLM-Decided

A critical architectural distinction in MCP that shapes all interaction flows:

**MCP Prompts** (e.g., `/find_images dogs`, `/start_code_mode`) are sent directly from the MCP client to the MCP server, **bypassing the LLM entirely**. The server executes a pre-designed workflow — a fixed sequence of queries, resource reads, and data assembly defined by the server developer. The server returns a list of messages that the LLM can use to compose its response. The LLM does not decide what to query or how to structure the result — it receives pre-assembled context.

**MCP Tools** (e.g., `find_images`, `get_image_details`) are invoked by the LLM during its reasoning. The LLM decides *when* to call a tool, *which* tool to call, and *what arguments* to pass. The tool executes on the server and returns results to the LLM, which then reasons about them and composes a response.

**Why this matters for design:**
- Prompt-triggered workflows are **deterministic** — same input always produces same server behavior regardless of which LLM hosts the client
- Tool calls are **LLM-dependent** — the LLM may call the wrong tool, pass wrong arguments, or not call a tool at all
- A prompt can internally use the same logic as a tool, but the orchestration is server-controlled, not LLM-controlled
- Prompts pre-load the LLM context with everything it needs for follow-up conversation (hierarchy context, narrowing suggestions, relationship data)

**In this design:**
- `/find_images {query}` is a prompt: server runs a workflow that queries views, assembles results + context, returns messages
- `/start_code_mode` is a prompt: server loads `00-mcp-reference.sql` as context, returns instructions
- `find_images(query)` is also a tool: LLM calls it during free-form conversation when it decides a search is needed
- The prompt and tool may share server-side implementation, but the entry path differs

---

## 1. Three Interaction Mechanisms

### tools/call -- Silent In-Widget Data Refresh

**What it does:** The widget calls an MCP tool directly via the App SDK bridge. The tool executes on the server and returns results to the widget. The widget re-renders with new data. No new conversation turn is created.

**Who initiates:** Widget (JavaScript in the iframe)

**What happens in conversation:** Nothing. The interaction is invisible to the conversation. The model does not see the request or response.

**Reliability:** HIGH. This is a direct tool invocation with no LLM reasoning in the loop. The widget gets exactly the tool response it requested.

**Code pattern:**
```javascript
// Widget calls find_images directly via App SDK bridge with current selection state
// Only include dimensions that have active selections — omit empty dimensions per schema
const args = { page: 1, limit: 20 };
if (activeSubjects.length === 1) args.subject = activeSubjects[0];
else if (activeSubjects.length > 1) args.subject = activeSubjects;
if (activeRelationships.length === 1) args.relationship = activeRelationships[0];
else if (activeRelationships.length > 1) args.relationship = activeRelationships;

const result = await app.callServerTool({ name: "find_images", arguments: args });
// Widget re-renders with the returned data
if (result?.structuredContent) {
  updateGrid(result.structuredContent, result._meta);
}
```

---

### ui/message -- Conversational Follow-Up (New Turn)

**What it does:** The widget posts a message to the conversation as if the user typed it. The LLM processes the message, reasons about it, and potentially calls a tool. This produces a new conversation turn below the current widget, potentially with a new widget.

**Who initiates:** Widget (on behalf of the user)

**What happens in conversation:** A new user message appears, followed by a new assistant response. The current widget freezes in place (becomes a historical artifact in the conversation).

**Reliability:** MEDIUM. The message goes through the LLM, which decides what to do. The LLM might respond with text instead of calling the expected tool. Community reports indicate `sendFollowUpMessage` / `ui/message` is inconsistent -- sometimes the LLM interprets the message differently than intended.

**Code pattern:**
```javascript
// Widget sends follow-up message to conversation
window.parent.postMessage({
  jsonrpc: "2.0",
  method: "ui/message",
  params: {
    role: "user",
    content: [{
      type: "text",
      text: "Show me details for image 000a1249af2bc5f0 [get_image_details]"
    }]
  }
}, "*");
```

---

### ui/update-model-context -- Silent Context Sync

**What it does:** The widget updates the model's context without generating a new conversation turn. The model becomes aware of the user's current state within the widget (what they are looking at, what they have selected) so that future user messages get better responses.

**Who initiates:** Widget (automatically, based on user interaction)

**What happens in conversation:** Nothing visible. The model's internal context is updated silently.

**Reliability:** MEDIUM-HIGH. The context update itself is reliable, but whether the model actually uses the updated context in future responses depends on the model's attention and reasoning.

**Code pattern:**
```javascript
// Widget updates model context when user scrolls or interacts
window.parent.postMessage({
  jsonrpc: "2.0",
  method: "ui/update-model-context",
  params: {
    context: {
      current_view: "results-grid",
      visible_images: ["000a1249af2bc5f0", "000b2349bf3cd6e1"],
      active_subjects: ["Poodle"],
      active_relationships: [],
      scroll_position: "middle"
    }
  }
}, "*");
```


## 2. Decision Tree

Use this tree to determine which mechanism to use for any widget interaction.

- **Is the user staying within the same search context?** --> `tools/call`
  - Facet click (category, relationship, confidence range) --> `tools/call find_images`
    - Widget constructs full args from current selection state (subject[], relationship[], object[], page)
    - Widget re-renders grid in place with filtered results
    - Active facets shown as toggled pills
  - Pagination (next/previous page) --> `tools/call find_images` with page param
    - Widget sends same args with incremented page
    - Widget updates image grid, preserves all active filters
  - Sort change (by confidence, by label count) --> `tools/call find_images`
    - Widget re-renders grid with same results in new order
  - Hierarchy node expand (in hierarchy browser widget) --> `tools/call explore_category`
    - Widget expands the tree node in place, showing children
    - No new conversation turn needed
  - Remove a facet toggle --> `tools/call find_images` without that value
    - Widget re-renders with broadened results

- **Is the user switching to a fundamentally different view?** --> `ui/message`
  - Click image thumbnail for detail view --> `ui/message`
    - Triggers: LLM calls `get_image_details`, producing a new image-detail widget
    - Message text: "Show me details for image {image_id} [get_image_details]"
    - Current results grid freezes; new detail widget appears below
  - "More with {subject}" from detail view (via `navigate_actions.by_subject[]`) --> `ui/message`
    - Triggers: LLM calls `find_images` with `{ subject }` from pre-computed args
    - Message text: "Find more images of {subject} [find_images]"
    - New results grid widget appears below the detail widget
  - "{subject} {relationship} {object}" from detail view (via `navigate_actions.by_relationship[]`) --> `ui/message`
    - Triggers: LLM calls `find_images` with `{ subject, relationship, object }` from pre-computed args (leaf→parent resolved)
    - Message text: "Find images where {subject} {relationship} {object} [find_images]"
  - "Explore {category}" from detail view (via `navigate_actions.explore_category`) --> `ui/message`
    - Triggers: LLM calls `explore_category` with `{ class_name }` from pre-computed args
    - Message text: "Explore the {class_name} category hierarchy [explore_category]"

- **Does the model need to know what the user is looking at?** --> `ui/update-model-context`
  - User scrolls to a different section of results
    - Context: which images are currently visible in the viewport
  - User toggles annotation layers in detail view (boxes, masks, relationships)
    - Context: which layers are active, what the user is focusing on
  - User expands a hierarchy branch in the browser
    - Context: which branch is expanded, current depth of exploration
  - User hovers over or selects a specific annotation
    - Context: the annotation details the user is examining


## 3. Fallback Patterns

Every `ui/message` action has a fallback for when the LLM does not trigger the expected tool. This addresses the known reliability issue with `sendFollowUpMessage`.

### Thumbnail Click --> get_image_details

**Primary path:** Widget sends `ui/message` with text: "Show me details for image {image_id} [get_image_details]"

**Fallback if no response after 5 seconds:**
- Widget displays a text prompt overlay on the clicked thumbnail:
  ```
  Try typing: "Show me details for image 000a1249af2bc5f0"
  ```
- The text is selectable so the user can copy-paste it into the conversation input

**Fallback if LLM responds with text (no tool call):**
- The conversation will contain a text response about the image
- The widget remains in grid view (no detail widget appears)
- Widget can detect this by listening for a new tool response -- if none arrives within 10 seconds, show the text fallback

### "More with {subject}" (navigate_actions.by_subject[])

**Primary path:** Widget sends `ui/message` with text: "Find more images of {subject} [find_images]"

**Fallback after 5 seconds:**
- Widget shows hint below the action button:
  ```
  Try typing: "Find more images of {subject}"
  ```

### "{subject} {relationship} {object}" (navigate_actions.by_relationship[])

**Primary path:** Widget sends `ui/message` with text: "Find images where {subject} {relationship} {object} [find_images]"

**Fallback after 5 seconds:**
- Widget shows hint:
  ```
  Try typing: "Find images where {subject} {relationship} {object}"
  ```

### "Explore {category}" (navigate_actions.explore_category)

**Primary path:** Widget sends `ui/message` with text: "Explore the {class_name} category hierarchy [explore_category]"

**Fallback after 5 seconds:**
- Widget shows hint:
  ```
  Try typing: "Show me the {class_name} category tree"
  ```

### Design Principles for ui/message Text

To maximize the probability that the LLM calls the right tool:

1. **Include the tool name hint** in brackets at the end: `[get_image_details]`
2. **Use the exact parameter names** from the tool's inputSchema: "image {image_id}" not "that picture"
3. **Be specific about the action**, not vague: "Find images where Person ride Horse" not "show me related things"
4. **Keep the message short** -- long messages give the LLM more room to interpret differently


## 4. Error Handling Patterns

### tools/call Timeout

**Behavior:** Show spinner for 3 seconds, then "Loading..." text, then error state with retry button after 10 seconds.

```
0-3s:    [Spinner animation]
3-10s:   "Loading results..."
10s+:    "Request timed out."
         [Retry] button
```

The retry button re-sends the same `tools/call` request. After 2 failed retries, show:
```
"Unable to load results. The server may be temporarily unavailable."
[Retry] [Close]
```

### tools/call Returns Empty Results

**Behavior:** Widget shows "No results" state with suggestions.

```
No images found matching "{query}" with filter "{filter}".

Suggestions:
- Remove the "{filter}" filter to broaden results
- Try a parent category (e.g., "Animal" instead of "Poodle")
- Check spelling of the class name

[Remove Filters] [New Search]
```

The "New Search" button sends a `ui/message` to start a fresh conversation turn.

### ui/message No Response

**Behavior:** Widget shows fallback text prompt after 5 seconds (see Fallback Patterns above).

If the LLM responds with text but no tool call, the user sees the text response in conversation. The widget displays a subtle hint:
```
Tip: You can also type your request directly in the conversation.
```

### Network Error

**Behavior:** Widget shows offline state. Does NOT retry automatically (to avoid hammering a down server).

```
"Network error. Please check your connection."
[Retry]
```

The retry button is the only way to re-attempt. No automatic retry loop.


## 5. Data Flow Diagrams

### Facet Click (tools/call -- Silent Refresh)

```
User clicks "Poodle" facet in results grid
  |
  v
Widget (results-grid.html)
  | Toggles "Poodle" in local activeSubjects[]
  | Constructs full find_images args from current selection state
  | app.callServerTool({ name: "find_images", arguments: { subject: "Poodle", page: 1 } })
  |
  v
MCP Server
  | SELECT ... FROM labeled_images li
  | JOIN class_hierarchy ch ON ...
  | WHERE ch.display_name = 'Poodle'
  |
  v
Athena (Trino SQL)
  | Query executes against Iceberg tables
  |
  v
MCP Server
  | Constructs three-layer response
  | { structuredContent, content, _meta }
  |
  v
Widget receives response
  | updateGrid(result.structuredContent, result._meta)
  |
  v
Widget re-renders with filtered Poodle images
  (No conversation turn created)
```

### Thumbnail Click (ui/message -- New Turn)

```
User clicks image thumbnail in results grid
  |
  v
Widget (results-grid.html)
  | postMessage({ method: "ui/message", params: { text: "Show me details for image 000a1249af2bc5f0 [get_image_details]" } })
  |
  v
Host (ChatGPT / Claude)
  | Injects user message into conversation
  |
  v
LLM reasons about the message
  | Decides to call get_image_details tool
  |
  v
MCP Server
  | SELECT ... FROM labeled_images WHERE image_id = '000a1249af2bc5f0'
  | SELECT ... FROM labeled_boxes WHERE image_id = '000a1249af2bc5f0'
  | SELECT ... FROM labeled_relationships WHERE image_id = '000a1249af2bc5f0'
  | SELECT ... FROM labeled_masks WHERE image_id = '000a1249af2bc5f0'
  |
  v
Athena (multiple queries)
  |
  v
MCP Server
  | Constructs three-layer response with all annotations
  |
  v
Host renders new widget below in conversation
  | image-detail.html widget appears with full annotations
  |
  v
New image-detail widget displayed
  (Original results grid freezes in place above)
```

### Hierarchy Expand (tools/call -- Silent Refresh)

```
User clicks "Dog" node in hierarchy browser
  |
  v
Widget (hierarchy-browser.html)
  | app.callServerTool({ name: "explore_category", arguments: { class_name: "Dog", depth: 2 } })
  |
  v
MCP Server
  | SELECT display_name, depth, edge_type, root_path, is_leaf
  | FROM class_hierarchy
  | WHERE root_path LIKE 'Entity > Animal > Carnivore > Dog%'
  | AND depth <= (SELECT depth FROM class_hierarchy WHERE display_name = 'Dog') + 2
  |
  v
Athena
  |
  v
MCP Server
  | Constructs response with hierarchy_tree and sample_images
  |
  v
Widget receives response
  | expandTreeNode("Dog", result._meta.hierarchy_tree)
  |
  v
Widget expands Dog node showing Poodle, German shepherd, Labrador, ...
  (No conversation turn created)
```


## 6. Visibility Matrix

| Tool | Model Visible | App (Widget) Visible | Rationale |
|------|:---:|:---:|-----------|
| find_images | Yes | Yes | Model calls on user query from conversation, decomposing NL into subject/object/relationship args. Widget calls via `tools/call` for facet filtering and pagination (constructing args from local selection state). |
| resolve_entity | Yes | Yes | Model calls to validate/normalize entity names before find_images when unsure. Widget calls for autocomplete or disambiguation. Lightweight lookup, no widget rendered. |
| get_image_details | Yes | Yes | Model calls from conversation when user asks about a specific image. Widget calls when user clicks a thumbnail (via `ui/message` triggering the model). |
| explore_category | Yes | Yes | Model calls when user asks about categories or hierarchy. Widget calls for tree node expansion via `tools/call` (silent in-widget refresh). |

### Visibility Design Principles

1. **Model-visible tools** handle new user intents that require LLM reasoning (understanding what the user wants, picking the right query parameters)
2. **Dual-visible tools** serve both paths: the model invokes them for conversational requests, and widgets invoke them for direct interactions
3. **All tools are dual-visible.** The widget uses `find_images` directly for facet refinement — the widget holds selection state locally and constructs complete `find_images` args on each interaction. The server is stateless; every call is self-contained.
