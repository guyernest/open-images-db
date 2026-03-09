# Interaction Model: Widget-Host Communication Patterns

This document defines the decision framework for choosing between MCP Apps interaction mechanisms. Every widget interaction in the Open Images design can be resolved by consulting this document.

## 1. Three Interaction Mechanisms

### tools/call -- Silent In-Widget Data Refresh

**What it does:** The widget calls an MCP tool directly via the App SDK bridge. The tool executes on the server and returns results to the widget. The widget re-renders with new data. No new conversation turn is created.

**Who initiates:** Widget (JavaScript in the iframe)

**What happens in conversation:** Nothing. The interaction is invisible to the conversation. The model does not see the request or response.

**Reliability:** HIGH. This is a direct tool invocation with no LLM reasoning in the loop. The widget gets exactly the tool response it requested.

**Code pattern:**
```javascript
// Widget calls tool directly via App SDK bridge
const result = await app.callServerTool({
  name: "narrow_results",
  arguments: {
    previous_query: currentQuery,
    filter: "category:Poodle",
    page: 1,
    limit: 20
  }
});
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
      active_filters: ["category:Poodle"],
      scroll_position: "middle"
    }
  }
}, "*");
```


## 2. Decision Tree

Use this tree to determine which mechanism to use for any widget interaction.

- **Is the user staying within the same search context?** --> `tools/call`
  - Facet click (category, relationship, confidence range) --> `tools/call narrow_results`
    - Widget re-renders grid in place with filtered results
    - Applied filters shown as removable chips above the grid
  - Pagination (next/previous page) --> `tools/call narrow_results` with page param
    - Widget updates image grid, preserves all active filters
    - Page indicator updates
  - Sort change (by confidence, by label count) --> `tools/call narrow_results`
    - Widget re-renders grid with same results in new order
  - Hierarchy node expand (in hierarchy browser widget) --> `tools/call explore_category`
    - Widget expands the tree node in place, showing children
    - No new conversation turn needed
  - Remove a filter chip --> `tools/call narrow_results` without that filter
    - Widget re-renders with broadened results

- **Is the user switching to a fundamentally different view?** --> `ui/message`
  - Click image thumbnail for detail view --> `ui/message`
    - Triggers: LLM calls `get_image_details`, producing a new image-detail widget
    - Message text: "Show me details for image {image_id} [get_image_details]"
    - Current results grid freezes; new detail widget appears below
  - "Show me more like this" from detail view --> `ui/message`
    - Triggers: LLM calls `find_images` with related query
    - Message text: "Find images similar to {image_id} with {primary_label} [find_images]"
    - New results grid widget appears below the detail widget
  - "What else is in this scene?" from detail view --> `ui/message`
    - Triggers: LLM calls `find_images` with relationship filter
    - Message text: "Find images with {relationship} involving {object} [find_images]"
  - "Browse this category" from detail view --> `ui/message`
    - Triggers: LLM calls `explore_category` with the object's parent class
    - Message text: "Explore the {category_name} category hierarchy [explore_category]"

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

### "Show Me More Like This"

**Primary path:** Widget sends `ui/message` with text: "Find images similar to {image_id} with {label} [find_images]"

**Fallback after 5 seconds:**
- Widget shows hint below the action button:
  ```
  Try typing: "Find more images of {label}"
  ```

### "What Else Is in This Scene?"

**Primary path:** Widget sends `ui/message` with text: "Find images with {relationship} involving {object_name} [find_images]"

**Fallback after 5 seconds:**
- Widget shows hint:
  ```
  Try typing: "Find images where something {relationship} a {object_name}"
  ```

### "Browse This Category"

**Primary path:** Widget sends `ui/message` with text: "Explore the {category_name} category hierarchy [explore_category]"

**Fallback after 5 seconds:**
- Widget shows hint:
  ```
  Try typing: "Show me the {category_name} category tree"
  ```

### Design Principles for ui/message Text

To maximize the probability that the LLM calls the right tool:

1. **Include the tool name hint** in brackets at the end: `[get_image_details]`
2. **Use the exact parameter names** from the tool's inputSchema: "image {image_id}" not "that picture"
3. **Be specific about the action**, not vague: "Find images with relationship:ride involving Horse" not "show me related things"
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
  | app.callServerTool({ name: "narrow_results", arguments: { filter: "category:Poodle" } })
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
| find_images | Yes | Yes | Model calls on user query from conversation. Widget calls for "more like this" or "same objects" via `ui/message` that triggers model to call this tool. |
| narrow_results | No | Yes | Widget-only for fast in-place filtering. Model should never call this directly -- it should use `find_images` for new searches. Keeping this app-only prevents the model from attempting to refine when it should start fresh. |
| get_image_details | Yes | Yes | Model calls from conversation when user asks about a specific image. Widget calls when user clicks a thumbnail (via `ui/message` triggering the model). |
| explore_category | Yes | Yes | Model calls when user asks about categories or hierarchy. Widget calls for tree node expansion via `tools/call` (silent in-widget refresh). |

### Visibility Design Principles

1. **Model-visible tools** handle new user intents that require LLM reasoning (understanding what the user wants, picking the right query parameters)
2. **App-only tools** handle deterministic widget interactions where the action is unambiguous (clicking a facet always means "filter by this value")
3. **Dual-visible tools** serve both paths: the model invokes them for conversational requests, and widgets invoke them for direct interactions
4. `narrow_results` is the only app-only tool because filtering is always a deterministic action within an existing context -- no LLM reasoning needed
