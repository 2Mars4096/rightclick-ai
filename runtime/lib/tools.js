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
  normalized = normalized.replace(/\s+([+-]\d{2}:?\d{2})$/, "$1");
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

const START_FIELD_NAMES = ["start", "startAt", "start_at", "startDate", "start_date", "date"];
const DIRECT_START_ARRAY_FIELD_NAMES = ["start", "startAt", "start_at"];
const END_FIELD_NAMES = ["end", "endAt", "end_at", "endDate", "end_date"];
const DATE_LIST_FIELD_NAMES = [
  "dates",
  "lectureDates",
  "lecture_dates",
  "occurrenceDates",
  "occurrence_dates",
  "days",
  "date",
  "startDate",
  "start_date",
  "start",
];
const OCCURRENCE_FIELD_NAMES = ["occurrences", "sessions", "instances"];
const TIME_RANGE_FIELD_NAMES = ["timeRange", "time_range", "times", "time", "hours"];
const START_TIME_FIELD_NAMES = ["startTime", "start_time", "beginTime", "begin_time"];
const END_TIME_FIELD_NAMES = ["endTime", "end_time", "finishTime", "finish_time"];

function ownProperty(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key);
}

function cloneObject(object) {
  const clone = {};
  for (const key in object) {
    if (ownProperty(object, key)) {
      clone[key] = object[key];
    }
  }
  return clone;
}

function deleteFields(object, names) {
  for (let index = 0; index < names.length; index += 1) {
    delete object[names[index]];
  }
}

function firstArrayField(object, names) {
  if (!object || typeof object !== "object") {
    return null;
  }
  for (let index = 0; index < names.length; index += 1) {
    const value = object[names[index]];
    if (Array.isArray(value) && value.length > 0) {
      return value;
    }
  }
  return null;
}

function firstScalarStringField(object, names) {
  if (!object || typeof object !== "object") {
    return "";
  }
  for (let index = 0; index < names.length; index += 1) {
    const value = object[names[index]];
    if (value === null || value === undefined || Array.isArray(value) || typeof value === "object") {
      continue;
    }
    const text = String(value).trim();
    if (text !== "") {
      return text;
    }
  }
  return "";
}

function datePartFromValue(value) {
  const text = stringOrEmpty(value);
  if (isDateOnly(text)) {
    return text;
  }
  const parsed = parseEventDate(text);
  if (!parsed) {
    return "";
  }
  return [
    parsed.getFullYear(),
    "-",
    pad(parsed.getMonth() + 1),
    "-",
    pad(parsed.getDate()),
  ].join("");
}

function parseTimeParts(value) {
  let text = stringOrEmpty(value).toLowerCase();
  if (text === "") {
    return null;
  }
  text = text.replace(/\./g, "").replace(/\s+/g, " ").trim();
  const match = text.match(/^(\d{1,2})(?::(\d{2}))?(?::(\d{2}))?\s*(am|pm)?$/);
  if (!match) {
    return null;
  }

  let hour = parseInt(match[1], 10);
  const minute = match[2] ? parseInt(match[2], 10) : 0;
  const second = match[3] ? parseInt(match[3], 10) : 0;
  const meridian = match[4] || "";

  if (minute > 59 || second > 59) {
    return null;
  }
  if (meridian !== "") {
    if (hour < 1 || hour > 12) {
      return null;
    }
    if (hour === 12) {
      hour = meridian === "am" ? 0 : 12;
    } else if (meridian === "pm") {
      hour += 12;
    }
  } else if (hour > 23) {
    return null;
  }

  return { hour: hour, minute: minute, second: second };
}

function isTimeOnlyValue(value) {
  return parseTimeParts(value) !== null;
}

function formatTimeParts(parts) {
  return [pad(parts.hour), ":", pad(parts.minute), ":", pad(parts.second)].join("");
}

function combineDateAndTime(dateValue, timeValue) {
  const datePart = datePartFromValue(dateValue);
  const timeParts = parseTimeParts(timeValue);
  if (datePart === "" || !timeParts) {
    return stringOrEmpty(dateValue);
  }
  return datePart + "T" + formatTimeParts(timeParts);
}

function parseTimeRange(value) {
  const text = stringOrEmpty(value);
  if (text === "") {
    return { start: "", end: "" };
  }

  const timePattern = /\b\d{1,2}(?::\d{2})(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?|am|pm)?\b|\b\d{1,2}\s*(?:a\.?m\.?|p\.?m\.?|am|pm)\b/gi;
  const matches = [];
  let match = null;
  while ((match = timePattern.exec(text)) !== null) {
    matches.push(match[0]);
  }

  if (matches.length >= 2) {
    return { start: matches[0], end: matches[1] };
  }
  if (matches.length === 1) {
    return { start: matches[0], end: "" };
  }
  return { start: "", end: "" };
}

function inferEventTimeRange(event, fallbackSource) {
  let startTime = firstScalarStringField(event, START_TIME_FIELD_NAMES);
  let endTime = firstScalarStringField(event, END_TIME_FIELD_NAMES);
  const startValue = firstScalarStringField(event, START_FIELD_NAMES);
  const endValue = firstScalarStringField(event, END_FIELD_NAMES);

  if (startTime === "" && isTimeOnlyValue(startValue)) {
    startTime = startValue;
  }
  if (endTime === "" && isTimeOnlyValue(endValue)) {
    endTime = endValue;
  }

  const rangeSource = firstScalarStringField(event, TIME_RANGE_FIELD_NAMES) || stringOrEmpty(fallbackSource);
  const range = parseTimeRange(rangeSource);
  if (startTime === "" && range.start !== "") {
    startTime = range.start;
  }
  if (endTime === "" && range.end !== "") {
    endTime = range.end;
  }

  return { start: startTime, end: endTime };
}

function monthNumberFromName(value) {
  const text = stringOrEmpty(value).toLowerCase().replace(/\./g, "");
  if (text.indexOf("jan") === 0) return 1;
  if (text.indexOf("feb") === 0) return 2;
  if (text.indexOf("mar") === 0) return 3;
  if (text.indexOf("apr") === 0) return 4;
  if (text === "may") return 5;
  if (text.indexOf("jun") === 0) return 6;
  if (text.indexOf("jul") === 0) return 7;
  if (text.indexOf("aug") === 0) return 8;
  if (text.indexOf("sep") === 0) return 9;
  if (text.indexOf("oct") === 0) return 10;
  if (text.indexOf("nov") === 0) return 11;
  if (text.indexOf("dec") === 0) return 12;
  return 0;
}

function validLocalDate(year, month, day) {
  const date = new Date(year, month - 1, day);
  if (date.getFullYear() !== year || date.getMonth() !== month - 1 || date.getDate() !== day) {
    return null;
  }
  return date;
}

function inferDateListDate(month, day, explicitYear, referenceDate, previousDate) {
  let year = explicitYear || referenceDate.getFullYear();
  let date = validLocalDate(year, month, day);
  if (!date) {
    return null;
  }

  if (explicitYear) {
    return date;
  }

  const referenceDay = new Date(referenceDate.getFullYear(), referenceDate.getMonth(), referenceDate.getDate());
  if (previousDate) {
    while (date < previousDate) {
      year += 1;
      date = validLocalDate(year, month, day);
      if (!date) {
        return null;
      }
    }
  } else if (date < referenceDay) {
    date = validLocalDate(year + 1, month, day);
  }

  return date;
}

function formatDateOnlyFromDate(date) {
  return [
    date.getFullYear(),
    "-",
    pad(date.getMonth() + 1),
    "-",
    pad(date.getDate()),
  ].join("");
}

function referenceDateFromValue(value) {
  const parsed = parseEventDate(value);
  if (parsed) {
    return parsed;
  }
  return new Date();
}

function parseNaturalDateList(value, referenceDate) {
  const monthPattern =
    "jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|jun(?:e)?|jul(?:y)?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?";
  const monthPresence = new RegExp("\\b(?:" + monthPattern + ")\\b", "i");
  const text = stringOrEmpty(value);
  if (!monthPresence.test(text)) {
    return [];
  }

  const pieces = text.replace(/\([^)]*\)/g, " ").split(/[,;\n]+/);
  const monthDayPattern = new RegExp(
    "\\b(" + monthPattern + ")\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?(?:\\s*,?\\s*(\\d{4}))?",
    "i"
  );
  const bareDayPattern = /^\s*(\d{1,2})(?:st|nd|rd|th)?(?:\s*,?\s*(\d{4}))?\s*$/i;
  const dates = [];
  let activeMonth = 0;
  let previousDate = null;

  for (let index = 0; index < pieces.length; index += 1) {
    const piece = pieces[index].trim();
    if (piece === "") {
      continue;
    }

    let match = piece.match(monthDayPattern);
    let month = 0;
    let day = 0;
    let explicitYear = 0;
    if (match) {
      month = monthNumberFromName(match[1]);
      day = parseInt(match[2], 10);
      explicitYear = match[3] ? parseInt(match[3], 10) : 0;
      activeMonth = month;
    } else {
      match = piece.match(bareDayPattern);
      if (!match || activeMonth === 0) {
        continue;
      }
      month = activeMonth;
      day = parseInt(match[1], 10);
      explicitYear = match[2] ? parseInt(match[2], 10) : 0;
    }

    const date = inferDateListDate(month, day, explicitYear, referenceDate, previousDate);
    if (!date) {
      continue;
    }
    dates.push(formatDateOnlyFromDate(date));
    previousDate = date;
  }

  return dates.length > 1 ? dates : [];
}

function splitDateList(value, referenceDate) {
  const text = stringOrEmpty(value);
  if (text === "") {
    return null;
  }

  const isoMatches = text.match(/\d{4}-\d{2}-\d{2}/g);
  if (isoMatches && isoMatches.length > 1) {
    return isoMatches;
  }

  const naturalDates = parseNaturalDateList(text, referenceDate);
  if (naturalDates.length > 1) {
    return naturalDates;
  }

  return null;
}

function firstDateListField(event, names, referenceDate) {
  if (!event || typeof event !== "object") {
    return null;
  }
  for (let index = 0; index < names.length; index += 1) {
    const value = event[names[index]];
    if (Array.isArray(value) && value.length > 0) {
      return { values: value, source: "" };
    }
    const dates = splitDateList(value, referenceDate);
    if (dates) {
      return { values: dates, source: stringOrEmpty(value) };
    }
  }
  return null;
}

function expandDateListEvent(event, dateValues, sourceText) {
  const expanded = [];
  const commonTimes = inferEventTimeRange(event, sourceText);
  const commonAllDay = toBoolean(event.allDay ?? event.all_day ?? event.allday);

  for (let index = 0; index < dateValues.length; index += 1) {
    const dateValue = dateValues[index];
    const clone = cloneObject(event);
    deleteFields(clone, DATE_LIST_FIELD_NAMES);

    if (dateValue && typeof dateValue === "object" && !Array.isArray(dateValue)) {
      for (const key in dateValue) {
        if (ownProperty(dateValue, key)) {
          clone[key] = dateValue[key];
        }
      }
      const occurrenceDate = firstScalarStringField(dateValue, ["date", "day", "startDate", "start_date", "start"]);
      const occurrenceTimes = inferEventTimeRange(dateValue, sourceText);
      const startTime = occurrenceTimes.start || commonTimes.start;
      const endTime = occurrenceTimes.end || commonTimes.end;
      if (occurrenceDate !== "" && startTime !== "" && !commonAllDay) {
        clone.start = combineDateAndTime(occurrenceDate, startTime);
      }
      if (occurrenceDate !== "" && endTime !== "" && !commonAllDay) {
        clone.end = combineDateAndTime(occurrenceDate, endTime);
      }
      expanded.push(clone);
      continue;
    }

    const dateText = stringOrEmpty(dateValue);
    clone.start = commonTimes.start !== "" && !commonAllDay ? combineDateAndTime(dateText, commonTimes.start) : dateText;
    if (commonTimes.end !== "" && !commonAllDay) {
      clone.end = combineDateAndTime(dateText, commonTimes.end);
    }
    expanded.push(clone);
  }

  return expanded;
}

function expandOccurrenceEvents(event, occurrenceValues, referenceDate) {
  const expanded = [];
  for (let index = 0; index < occurrenceValues.length; index += 1) {
    const occurrence = occurrenceValues[index];
    if (occurrence && typeof occurrence === "object" && !Array.isArray(occurrence)) {
      const clone = cloneObject(event);
      deleteFields(clone, OCCURRENCE_FIELD_NAMES);
      for (const key in occurrence) {
        if (ownProperty(occurrence, key)) {
          clone[key] = occurrence[key];
        }
      }
      expanded.push(clone);
      continue;
    }

    const splitDates = splitDateList(occurrence, referenceDate);
    if (splitDates) {
      expanded.push.apply(expanded, expandDateListEvent(event, splitDates, stringOrEmpty(occurrence)));
      continue;
    }

    const clone = cloneObject(event);
    deleteFields(clone, OCCURRENCE_FIELD_NAMES);
    clone.start = stringOrEmpty(occurrence);
    expanded.push(clone);
  }
  return expanded;
}

function expandStartArrayEvents(event, startValues) {
  const expanded = [];
  const endValues = firstArrayField(event, END_FIELD_NAMES);
  const scalarEnd = firstScalarStringField(event, END_FIELD_NAMES);
  const commonTimes = inferEventTimeRange(event, "");
  const commonAllDay = toBoolean(event.allDay ?? event.all_day ?? event.allday);

  for (let index = 0; index < startValues.length; index += 1) {
    const clone = cloneObject(event);
    const startText = stringOrEmpty(startValues[index]);
    clone.start =
      commonTimes.start !== "" && !commonAllDay && isDateOnly(startText)
        ? combineDateAndTime(startText, commonTimes.start)
        : startText;
    if (endValues && index < endValues.length) {
      clone.end = stringOrEmpty(endValues[index]);
    } else if (commonTimes.end !== "" && !commonAllDay) {
      clone.end = combineDateAndTime(startText, commonTimes.end);
    } else if (scalarEnd !== "") {
      clone.end = isTimeOnlyValue(scalarEnd) ? combineDateAndTime(clone.start, scalarEnd) : scalarEnd;
    }
    expanded.push(clone);
  }

  return expanded;
}

function expandEvent(event, referenceDate) {
  if (!event || typeof event !== "object" || Array.isArray(event)) {
    return [event];
  }

  const startValues = firstArrayField(event, DIRECT_START_ARRAY_FIELD_NAMES);
  if (startValues) {
    return expandStartArrayEvents(event, startValues);
  }

  const occurrenceValues = firstArrayField(event, OCCURRENCE_FIELD_NAMES);
  if (occurrenceValues) {
    return expandOccurrenceEvents(event, occurrenceValues, referenceDate);
  }

  const dateList = firstDateListField(event, DATE_LIST_FIELD_NAMES, referenceDate);
  if (dateList) {
    return expandDateListEvent(event, dateList.values, dateList.source);
  }

  return [event];
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

  const timeRange = inferEventTimeRange(event, "");
  const eventDateText = firstScalarStringField(event, ["date", "day", "startDate", "start_date"]);
  if (isTimeOnlyValue(startText) && eventDateText !== "") {
    startText = combineDateAndTime(eventDateText, startText);
  }
  if (isDateOnly(startText) && !allDay && timeRange.start !== "") {
    startText = combineDateAndTime(startText, timeRange.start);
  }
  if (endText !== "" && isDateOnly(endText) && !allDay && timeRange.end !== "") {
    endText = combineDateAndTime(endText, timeRange.end);
  }
  if (endText !== "" && isTimeOnlyValue(endText) && !allDay) {
    endText = combineDateAndTime(startText, endText);
  }
  if (endText === "" && !allDay && timeRange.end !== "") {
    endText = combineDateAndTime(startText, timeRange.end);
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
    const referenceDate = referenceDateFromValue(argv[3]);
    const rawEvents = Array.isArray(root.events) ? root.events : [];
    const normalized = [];
    for (let index = 0; index < rawEvents.length; index += 1) {
      const expandedEvents = expandEvent(rawEvents[index], referenceDate);
      for (let expandedIndex = 0; expandedIndex < expandedEvents.length; expandedIndex += 1) {
        const event = normalizeEvent(expandedEvents[expandedIndex], defaultMinutes);
        if (event) {
          normalized.push(event);
        }
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
