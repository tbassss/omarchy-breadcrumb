.pragma library

function stateLabel(state) {
  if (state === "in_progress") return "In progress"
  if (state === "waiting") return "Waiting"
  if (state === "done") return "Done"
  if (state === "ready") return "Ready"
  return ""
}

function stateOptions() {
  return [
    { value: "ready", label: "Ready" },
    { value: "in_progress", label: "In progress" },
    { value: "waiting", label: "Waiting" },
    { value: "done", label: "Done" }
  ]
}

function kindOptions() {
  return [
    { value: "web", label: "Web" },
    { value: "file", label: "File" },
    { value: "folder", label: "Folder" }
  ]
}

function parseResponse(text) {
  var raw = String(text || "").trim()
  if (!raw)
    return { ok: false, error: "io", message: "The store returned no result." }
  try {
    var parsed = JSON.parse(raw)
    if (!parsed || typeof parsed !== "object")
      return { ok: false, error: "io", message: "The store returned invalid JSON." }
    return parsed
  } catch (e) {
    return { ok: false, error: "io", message: "The store returned invalid JSON." }
  }
}

function fileFromUrl(url) {
  var path = String(url || "")
  if (path.indexOf("file://") === 0)
    path = path.slice(7)
  return path
}

function defaultAuthor() {
  return "You"
}
