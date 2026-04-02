#!/usr/bin/osascript -l JavaScript

ObjC.import('Foundation');

function readText(path) {
  const value = $.NSString.stringWithContentsOfFileEncodingError(
    $(path),
    $.NSUTF8StringEncoding,
    null
  );
  if (!value || value.isNil()) {
    throw new Error("Could not read " + path);
  }
  return ObjC.unwrap(value);
}

function writeStdout(text) {
  const data = $(String(text)).dataUsingEncoding($.NSUTF8StringEncoding);
  $.NSFileHandle.fileHandleWithStandardOutput.writeData(data);
}

function pad(value) {
  return String(value).padStart(2, "0");
}

function offsetString(date) {
  const minutes = -date.getTimezoneOffset();
  const sign = minutes >= 0 ? "+" : "-";
  const absolute = Math.abs(minutes);
  return sign + pad(Math.floor(absolute / 60)) + pad(absolute % 60);
}

function formatAppleScriptDate(date) {
  return [
    date.getFullYear(),
    "-",
    pad(date.getMonth() + 1),
    "-",
    pad(date.getDate()),
    " ",
    pad(date.getHours()),
    ":",
    pad(date.getMinutes()),
    ":",
    pad(date.getSeconds()),
    " ",
    offsetString(date),
  ].join("");
}

function isDateOnly(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(value);
}

function shiftDateOnly(dateOnly, days) {
  const date = new Date(dateOnly + "T00:00:00");
  date.setDate(date.getDate() + days);
  return [
    date.getFullYear(),
    "-",
    pad(date.getMonth() + 1),
    "-",
    pad(date.getDate()),
  ].join("");
}

function normalizeDateTimeString(value) {
  let normalized = String(value).trim();
  if (/^\d{4}-\d{2}-\d{2} \d/.test(normalized)) {
    normalized = normalized.replace(" ", "T");
  }
  normalized = normalized.replace(/\.(\d+)(Z|[+-]\d{2}:?\d{2})$/, "$2");
  normalized = normalized.replace(/([+-]\d{2})(\d{2})$/, "$1:$2");
  return normalized;
}

function parseEventDate(value) {
  if (value === null || value === undefined) {
    return null;
  }
  const text = String(value).trim();
  if (text === "") {
    return null;
  }
  if (isDateOnly(text)) {
    return new Date(text + "T00:00:00");
  }
  const date = new Date(normalizeDateTimeString(text));
  if (Number.isNaN(date.getTime())) {
    return null;
  }
  return date;
}

function toBoolean(value) {
  if (typeof value === "boolean") {
    return value;
  }
  if (typeof value === "number") {
    return value !== 0;
  }
  if (typeof value === "string") {
    return /^(1|true|yes|y)$/i.test(value.trim());
  }
  return false;
}

function firstString() {
  for (let index = 0; index < arguments.length; index += 1) {
    const value = arguments[index];
    if (value !== null && value !== undefined && String(value).trim() !== "") {
      return String(value).trim();
    }
  }
  return "";
}

function stringOrEmpty(value) {
  if (value === null || value === undefined) {
    return "";
  }
  return String(value).trim();
}

function stripMarkdownFences(value) {
  const text = String(value).trim();
  const match = text.match(/^```(?:[\w-]+)?\s*([\s\S]*?)```$/);
  if (match && match[1]) {
    return match[1].trim();
  }
  return text;
}

function findBalancedBlock(source, opening, closing) {
  let start = -1;
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = 0; index < source.length; index += 1) {
    const char = source[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char === "\\") {
        escaped = true;
      } else if (char === "\"") {
        inString = false;
      }
      continue;
    }
    if (char === "\"") {
      inString = true;
      continue;
    }
    if (char === opening) {
      if (depth === 0) {
        start = index;
      }
      depth += 1;
      continue;
    }
    if (char === closing && depth > 0) {
      depth -= 1;
      if (depth === 0 && start >= 0) {
        return source.slice(start, index + 1);
      }
    }
  }
  return "";
}

function extractJsonCandidate(source) {
  const trimmed = source.trim();
  const candidates = [];
  if (trimmed !== "") {
    candidates.push(trimmed);
  }

  const fencedMatch = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fencedMatch && fencedMatch[1]) {
    candidates.push(fencedMatch[1].trim());
  }

  const objectCandidate = findBalancedBlock(trimmed, "{", "}");
  if (objectCandidate !== "") {
    candidates.push(objectCandidate);
  }

  const arrayCandidate = findBalancedBlock(trimmed, "[", "]");
  if (arrayCandidate !== "") {
    candidates.push(arrayCandidate);
  }

  for (let index = 0; index < candidates.length; index += 1) {
    try {
      return JSON.parse(candidates[index]);
    } catch (error) {
      continue;
    }
  }

  throw new Error("The model response did not contain valid JSON.");
}

function normalizeEvent(event, defaultMinutes) {
  const title = firstString(event.title, event.summary, event.name, event.subject);
  if (title === "") {
    return null;
  }

  let startText = firstString(
    event.start,
    event.startAt,
    event.start_at,
    event.startDate,
    event.start_date,
    event.date
  );
  let endText = firstString(
    event.end,
    event.endAt,
    event.end_at,
    event.endDate,
    event.end_date
  );
  let allDay = toBoolean(event.allDay ?? event.all_day ?? event.allday);

  if (startText === "") {
    return null;
  }

  if (isDateOnly(startText)) {
    allDay = true;
  }

  if (allDay) {
    if (!isDateOnly(startText)) {
      const parsedStart = parseEventDate(startText);
      if (!parsedStart) {
        return null;
      }
      startText = [
        parsedStart.getFullYear(),
        "-",
        pad(parsedStart.getMonth() + 1),
        "-",
        pad(parsedStart.getDate()),
      ].join("");
    }

    if (endText === "") {
      endText = shiftDateOnly(startText, 1);
    } else if (!isDateOnly(endText)) {
      const parsedEnd = parseEventDate(endText);
      if (!parsedEnd) {
        return null;
      }
      endText = [
        parsedEnd.getFullYear(),
        "-",
        pad(parsedEnd.getMonth() + 1),
        "-",
        pad(parsedEnd.getDate()),
      ].join("");
    }

    if (endText <= startText) {
      endText = shiftDateOnly(startText, 1);
    }

    return {
      title: title,
      start: formatAppleScriptDate(parseEventDate(startText)),
      end: formatAppleScriptDate(parseEventDate(endText)),
      allDay: true,
      location: firstString(event.location, event.venue),
      notes: firstString(event.notes, event.description, event.details),
      calendar: firstString(event.calendar, event.calendarName, event.calendar_name),
    };
  }

  const startDate = parseEventDate(startText);
  if (!startDate) {
    return null;
  }

  let endDate = parseEventDate(endText);
  if (!endDate) {
    endDate = new Date(startDate.getTime() + defaultMinutes * 60 * 1000);
  }

  if (endDate <= startDate) {
    endDate = new Date(startDate.getTime() + defaultMinutes * 60 * 1000);
  }

  return {
    title: title,
    start: formatAppleScriptDate(startDate),
    end: formatAppleScriptDate(endDate),
    allDay: false,
    location: firstString(event.location, event.venue),
    notes: firstString(event.notes, event.description, event.details),
    calendar: firstString(event.calendar, event.calendarName, event.calendar_name),
  };
}

function base64(text) {
  const data = $(String(text)).dataUsingEncoding($.NSUTF8StringEncoding);
  return ObjC.unwrap(data.base64EncodedStringWithOptions(0));
}

function loadNormalizedDocument(path) {
  const parsed = JSON.parse(readText(path));
  return {
    reason: stringOrEmpty(parsed.reason),
    events: Array.isArray(parsed.events) ? parsed.events : [],
  };
}

function actionSystemPrompt(value) {
  const text = stringOrEmpty(value);
  if (text !== "") {
    return text;
  }
  return "Follow the user's instructions exactly. Return only the requested output format.";
}

function normalizeSummary(rawText) {
  const trimmed = stripMarkdownFences(rawText);
  if (trimmed === "") {
    throw new Error("The model did not return a summary.");
  }

  try {
    const parsed = extractJsonCandidate(trimmed);
    if (typeof parsed === "string") {
      const summary = stripMarkdownFences(parsed);
      if (summary !== "") {
        return summary;
      }
    }
    if (parsed && typeof parsed === "object") {
      const summary = firstString(parsed.summary, parsed.output, parsed.text, parsed.result);
      if (summary !== "") {
        return summary;
      }
      if (Array.isArray(parsed.bullets)) {
        const bulletText = parsed.bullets
          .map(function (item) {
            return stringOrEmpty(item);
          })
          .filter(function (item) {
            return item !== "";
          })
          .join("\n");
        if (bulletText !== "") {
          return bulletText;
        }
      }
      if (stringOrEmpty(parsed.reason) !== "") {
        throw new Error(stringOrEmpty(parsed.reason));
      }
    }
  } catch (error) {
    return trimmed;
  }

  return trimmed;
}

function normalizeListEntry(value) {
  if (value === null || value === undefined) {
    return "";
  }
  if (typeof value === "string") {
    return stripMarkdownFences(value).trim();
  }
  if (typeof value === "object") {
    return firstString(value.task, value.title, value.item, value.text, value.description, value.name);
  }
  return stringOrEmpty(value);
}

function normalizeBulletList(values) {
  if (!Array.isArray(values)) {
    return "";
  }

  const items = values
    .map(function (item) {
      return normalizeListEntry(item);
    })
    .filter(function (item) {
      return item !== "";
    });

  if (items.length === 0) {
    return "";
  }

  return items
    .map(function (item) {
      return "- " + item;
    })
    .join("\n");
}

function normalizeTextOutput(rawText, mode) {
  const trimmed = stripMarkdownFences(rawText);
  if (trimmed === "") {
    throw new Error("The model did not return any output.");
  }

  try {
    const parsed = extractJsonCandidate(trimmed);
    if (typeof parsed === "string") {
      const text = stripMarkdownFences(parsed).trim();
      if (text !== "") {
        return text;
      }
    }

    if (Array.isArray(parsed)) {
      const list = normalizeBulletList(parsed);
      if (list !== "") {
        return list;
      }
    }

    if (parsed && typeof parsed === "object") {
      if (mode === "rewrite") {
        const rewritten = firstString(
          parsed.rewrittenText,
          parsed.rewrite,
          parsed.rewritten,
          parsed.output,
          parsed.text,
          parsed.result,
          parsed.summary
        );
        if (rewritten !== "") {
          return stripMarkdownFences(rewritten).trim();
        }
      }

      const list = normalizeBulletList(
        parsed.actionItems ??
          parsed.action_items ??
          parsed.items ??
          parsed.tasks ??
          parsed.bullets ??
          parsed.checklist ??
          parsed.results
      );
      if (list !== "") {
        return list;
      }

      const text = firstString(parsed.output, parsed.text, parsed.result, parsed.summary);
      if (text !== "") {
        return stripMarkdownFences(text).trim();
      }

      if (stringOrEmpty(parsed.reason) !== "") {
        throw new Error(stringOrEmpty(parsed.reason));
      }
    }
  } catch (error) {
    return trimmed;
  }

  return trimmed;
}

function normalizeTemperature(value, fallback) {
  const parsed = Number(value);
  if (Number.isFinite(parsed)) {
    return parsed;
  }
  return fallback;
}

function buildOpenAIChatPayload(prompt, model, systemPrompt, temperature) {
  return {
    model: model,
    temperature: normalizeTemperature(temperature, 0.1),
    messages: [
      {
        role: "system",
        content: actionSystemPrompt(systemPrompt),
      },
      {
        role: "user",
        content: prompt,
      },
    ],
  };
}

function buildAnthropicPayload(prompt, model, systemPrompt) {
  return {
    model: model,
    max_tokens: 1200,
    temperature: 0.1,
    system: actionSystemPrompt(systemPrompt),
    messages: [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: prompt,
          },
        ],
      },
    ],
  };
}

function buildGeminiPayload(prompt, systemPrompt) {
  return {
    generationConfig: {
      temperature: 0.1,
    },
    contents: [
      {
        role: "user",
        parts: [
          {
            text: actionSystemPrompt(systemPrompt) + "\n\n" + prompt,
          },
        ],
      },
    ],
  };
}

function renderPrompt(templatePath, inputPath, currentDateTime, currentTimezone, defaultDuration, userInstruction) {
  const inputText = readText(inputPath);
  const nonEmptyLines = inputText
    .split(/\r?\n/)
    .map(function (line) {
      return line.trim();
    })
    .filter(function (line) {
      return line !== "";
    });
  const lineItems =
    nonEmptyLines.length === 0
      ? "(none)"
      : nonEmptyLines
          .map(function (line, index) {
            return String(index + 1) + ". " + line;
          })
          .join("\n");
  const normalizedInstruction = stringOrEmpty(userInstruction) === "" ? "(none)" : String(userInstruction).trim();

  return readText(templatePath)
    .split("{{CURRENT_LOCAL_DATETIME}}")
    .join(currentDateTime)
    .split("{{CURRENT_TIMEZONE}}")
    .join(currentTimezone)
    .split("{{DEFAULT_DURATION_MINUTES}}")
    .join(String(defaultDuration))
    .split("{{INPUT_NON_EMPTY_LINE_COUNT}}")
    .join(String(nonEmptyLines.length))
    .split("{{INPUT_LINE_ITEMS}}")
    .join(lineItems)
    .split("{{USER_INSTRUCTION}}")
    .join(normalizedInstruction)
    .split("{{INPUT_TEXT}}")
    .join(inputText);
}

function run(argv) {
  const command = argv[0];
  if (command === "build-openai-chat-payload") {
    writeStdout(JSON.stringify(buildOpenAIChatPayload(readText(argv[1]), argv[2], argv[3], argv[4])) + "\n");
    return;
  }
  if (command === "build-anthropic-payload") {
    writeStdout(JSON.stringify(buildAnthropicPayload(readText(argv[1]), argv[2], argv[3])) + "\n");
    return;
  }
  if (command === "build-gemini-payload") {
    writeStdout(JSON.stringify(buildGeminiPayload(readText(argv[1]), argv[2])) + "\n");
    return;
  }
  if (command === "render-prompt") {
    writeStdout(renderPrompt(argv[1], argv[2], argv[3], argv[4], argv[5], argv[6]));
    return;
  }
  if (command === "normalize-events") {
    const parsed = extractJsonCandidate(readText(argv[1]));
    const root =
      Array.isArray(parsed) ? { events: parsed } : parsed && typeof parsed === "object" ? parsed : { events: [] };
    const defaultMinutes = Math.max(parseInt(argv[2] || "60", 10) || 60, 1);
    const rawEvents = Array.isArray(root.events) ? root.events : [];
    const normalized = [];
    for (let index = 0; index < rawEvents.length; index += 1) {
      const event = normalizeEvent(rawEvents[index], defaultMinutes);
      if (event) {
        normalized.push(event);
      }
    }
    writeStdout(
      JSON.stringify({
        reason: stringOrEmpty(root.reason),
        events: normalized,
      }) + "\n"
    );
    return;
  }
  if (command === "emit-event-lines") {
    const doc = loadNormalizedDocument(argv[1]);
    for (let index = 0; index < doc.events.length; index += 1) {
      const event = doc.events[index];
      writeStdout(
        [
          base64(stringOrEmpty(event.title)),
          stringOrEmpty(event.start),
          stringOrEmpty(event.end),
          event.allDay ? "1" : "0",
          base64(stringOrEmpty(event.location)),
          base64(stringOrEmpty(event.notes)),
          base64(stringOrEmpty(event.calendar)),
        ].join("\t") + "\n"
      );
    }
    return;
  }
  if (command === "event-count") {
    const doc = loadNormalizedDocument(argv[1]);
    writeStdout(String(doc.events.length) + "\n");
    return;
  }
  if (command === "reason") {
    const doc = loadNormalizedDocument(argv[1]);
    writeStdout(doc.reason + "\n");
    return;
  }
  if (command === "normalize-summary") {
    writeStdout(normalizeSummary(readText(argv[1])) + "\n");
    return;
  }
  if (command === "normalize-text-output") {
    writeStdout(normalizeTextOutput(readText(argv[1]), argv[2] || "text") + "\n");
    return;
  }
  throw new Error("Unknown command: " + command);
}
