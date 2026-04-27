const rows = [];
const knownCategories = new Set();
const knownEvents = new Set();

let source = null;
let paused = false;
let selectedRow = null;

const elements = {
  status: document.getElementById("connectionStatus"),
  totalCount: document.getElementById("totalCount"),
  visibleCount: document.getElementById("visibleCount"),
  lastEventTime: document.getElementById("lastEventTime"),
  severityFilter: document.getElementById("severityFilter"),
  categoryFilter: document.getElementById("categoryFilter"),
  eventFilter: document.getElementById("eventFilter"),
  searchInput: document.getElementById("searchInput"),
  pauseButton: document.getElementById("pauseButton"),
  clearButton: document.getElementById("clearButton"),
  logRows: document.getElementById("logRows"),
  emptyDetails: document.getElementById("emptyDetails"),
  selectedDetails: document.getElementById("selectedDetails"),
  detailEvent: document.getElementById("detailEvent"),
  detailTrace: document.getElementById("detailTrace"),
  detailMission: document.getElementById("detailMission"),
  rawLine: document.getElementById("rawLine"),
  eventMessage: document.getElementById("eventMessage"),
};

function connect() {
  disconnect();
  setStatus("Connecting", "");
  source = new EventSource("/events");

  source.addEventListener("open", () => {
    if (!paused) {
      setStatus("Live", "live");
    }
  });

  source.addEventListener("log", (event) => {
    appendRawLog(event.data);
  });

  source.addEventListener("error", () => {
    if (!paused) {
      setStatus("Disconnected", "error");
    }
  });
}

function disconnect() {
  if (source) {
    source.close();
    source = null;
  }
}

function setStatus(text, className) {
  elements.status.textContent = text;
  elements.status.className = `status ${className}`.trim();
}

function appendRawLog(raw) {
  const row = decodeRow(raw);
  rows.push(row);
  addFilterValues(row);
  row.element = createTableRow(row);
  elements.logRows.appendChild(row.element);
  updateCounts();
  elements.lastEventTime.textContent = row.time || "-";
  applyFilters();
}

function decodeRow(raw) {
  let wrapper = null;
  let payload = null;
  let eventMessage = "";

  try {
    wrapper = JSON.parse(raw);
  } catch (_) {
    wrapper = null;
  }

  if (wrapper && typeof wrapper.eventMessage === "string") {
    eventMessage = wrapper.eventMessage;
    const trimmed = eventMessage.trim();
    if (trimmed.startsWith("{")) {
      try {
        payload = JSON.parse(trimmed);
      } catch (_) {
        payload = null;
      }
    }
  }

  const time = directValue(payload, wrapper, ["recorded_at", "timestamp", "date"]);
  const severity = directValue(payload, wrapper, ["severity", "messageType", "level"]);
  const category = directValue(payload, wrapper, ["category"]);
  const event = directValue(payload, wrapper, ["event"]);
  const trace = directValue(payload, wrapper, ["trace_id"]);
  const mission = directValue(payload, wrapper, ["mission_id"]);
  const operation = directValue(payload, wrapper, ["operation"]);
  const tool = directValue(payload, wrapper, ["tool_name"]);
  const processKind = directValue(payload, wrapper, ["process_kind"]);
  const duration = directValue(payload, wrapper, ["duration_ms"]);

  return {
    raw,
    wrapper,
    payload,
    eventMessage,
    time: stringifyCell(time),
    severity: stringifyCell(severity).toLowerCase(),
    category: stringifyCell(category),
    event: stringifyCell(event),
    trace: stringifyCell(trace),
    mission: stringifyCell(mission),
    operation: stringifyCell(operation),
    tool: stringifyCell(tool),
    processKind: stringifyCell(processKind),
    duration: stringifyCell(duration),
    durationNumber: Number(duration),
    element: null,
  };
}

function directValue(payload, wrapper, keys) {
  for (const key of keys) {
    if (payload && Object.prototype.hasOwnProperty.call(payload, key)) {
      return payload[key];
    }
    if (wrapper && Object.prototype.hasOwnProperty.call(wrapper, key)) {
      return wrapper[key];
    }
  }
  return "";
}

function stringifyCell(value) {
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "object") {
    return JSON.stringify(value);
  }
  return String(value);
}

function addFilterValues(row) {
  if (row.category && !knownCategories.has(row.category)) {
    knownCategories.add(row.category);
    addOption(elements.categoryFilter, row.category);
  }

  if (row.event && !knownEvents.has(row.event)) {
    knownEvents.add(row.event);
    addOption(elements.eventFilter, row.event);
  }
}

function addOption(select, value) {
  const option = document.createElement("option");
  option.value = value;
  option.textContent = value;
  select.appendChild(option);
}

function createTableRow(row) {
  const tr = document.createElement("tr");
  const severityClass = row.severity ? `severity-${row.severity}` : "";
  if (severityClass) {
    tr.classList.add(severityClass);
  }

  if (Number.isFinite(row.durationNumber)) {
    if (row.durationNumber >= 5000) {
      tr.classList.add("duration-slow");
    } else if (row.durationNumber >= 1000) {
      tr.classList.add("duration-warn");
    }
  }

  [
    row.time,
    row.severity,
    row.category,
    row.event,
    row.trace,
    row.mission,
    row.operation,
    row.tool,
    row.processKind,
    row.duration,
  ].forEach((value) => {
    const td = document.createElement("td");
    td.textContent = value;
    td.title = value;
    tr.appendChild(td);
  });

  tr.addEventListener("click", () => {
    selectRow(row);
  });

  return tr;
}

function selectRow(row) {
  if (selectedRow && selectedRow.element) {
    selectedRow.element.classList.remove("selected");
  }

  selectedRow = row;
  if (row.element) {
    row.element.classList.add("selected");
  }

  elements.emptyDetails.classList.add("hidden");
  elements.selectedDetails.classList.remove("hidden");
  elements.detailEvent.textContent = row.event || "-";
  elements.detailTrace.textContent = row.trace || "-";
  elements.detailMission.textContent = row.mission || "-";
  elements.rawLine.textContent = row.raw;
  elements.eventMessage.textContent = row.eventMessage || "";
}

function applyFilters() {
  const severity = elements.severityFilter.value;
  const category = elements.categoryFilter.value;
  const event = elements.eventFilter.value;
  const search = elements.searchInput.value.trim().toLowerCase();
  let visible = 0;

  for (const row of rows) {
    const matchesSeverity = !severity || row.severity === severity;
    const matchesCategory = !category || row.category === category;
    const matchesEvent = !event || row.event === event;
    const matchesSearch = !search || row.raw.toLowerCase().includes(search);
    const visibleRow = matchesSeverity && matchesCategory && matchesEvent && matchesSearch;

    if (row.element) {
      row.element.hidden = !visibleRow;
    }
    if (visibleRow) {
      visible += 1;
    }
  }

  elements.visibleCount.textContent = String(visible);
}

function updateCounts() {
  elements.totalCount.textContent = String(rows.length);
}

function clearRows() {
  rows.length = 0;
  knownCategories.clear();
  knownEvents.clear();
  elements.logRows.textContent = "";
  resetSelect(elements.categoryFilter);
  resetSelect(elements.eventFilter);
  elements.totalCount.textContent = "0";
  elements.visibleCount.textContent = "0";
  elements.lastEventTime.textContent = "-";
  elements.emptyDetails.classList.remove("hidden");
  elements.selectedDetails.classList.add("hidden");
  selectedRow = null;
}

function resetSelect(select) {
  const first = select.options[0];
  select.textContent = "";
  select.appendChild(first);
  select.value = "";
}

function togglePause() {
  paused = !paused;
  if (paused) {
    disconnect();
    setStatus("Paused", "paused");
    elements.pauseButton.textContent = "Resume";
  } else {
    elements.pauseButton.textContent = "Pause";
    connect();
  }
}

[
  elements.severityFilter,
  elements.categoryFilter,
  elements.eventFilter,
  elements.searchInput,
].forEach((control) => {
  control.addEventListener("input", applyFilters);
  control.addEventListener("change", applyFilters);
});

elements.pauseButton.addEventListener("click", togglePause);
elements.clearButton.addEventListener("click", clearRows);

connect();
