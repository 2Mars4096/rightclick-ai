on monthFromNumber(monthNumber)
  if monthNumber is 1 then return January
  if monthNumber is 2 then return February
  if monthNumber is 3 then return March
  if monthNumber is 4 then return April
  if monthNumber is 5 then return May
  if monthNumber is 6 then return June
  if monthNumber is 7 then return July
  if monthNumber is 8 then return August
  if monthNumber is 9 then return September
  if monthNumber is 10 then return October
  if monthNumber is 11 then return November
  if monthNumber is 12 then return December
  error "Unsupported month number: " & monthNumber
end monthFromNumber

on parseNormalizedDate(textValue)
  set sourceText to textValue as text

  if (count of sourceText) is 10 then
    set yearNumber to (text 1 thru 4 of sourceText) as integer
    set monthNumber to (text 6 thru 7 of sourceText) as integer
    set dayNumber to (text 9 thru 10 of sourceText) as integer

    set parsedDate to current date
    set year of parsedDate to yearNumber
    set month of parsedDate to my monthFromNumber(monthNumber)
    set day of parsedDate to dayNumber
    set time of parsedDate to 0
    return parsedDate
  end if

  if (count of sourceText) is less than 19 then error "Unsupported date format: " & sourceText

  set yearNumber to (text 1 thru 4 of sourceText) as integer
  set monthNumber to (text 6 thru 7 of sourceText) as integer
  set dayNumber to (text 9 thru 10 of sourceText) as integer
  set hourNumber to (text 12 thru 13 of sourceText) as integer
  set minuteNumber to (text 15 thru 16 of sourceText) as integer
  set secondNumber to (text 18 thru 19 of sourceText) as integer

  set parsedDate to current date
  set year of parsedDate to yearNumber
  set month of parsedDate to my monthFromNumber(monthNumber)
  set day of parsedDate to dayNumber
  set time of parsedDate to ((hourNumber * hours) + (minuteNumber * minutes) + secondNumber)
  return parsedDate
end parseNormalizedDate

on run argv
  if (count of argv) is less than 7 then error "Expected 7 arguments."

  set calendarName to item 1 of argv
  set eventTitle to item 2 of argv
  set startText to item 3 of argv
  set endText to item 4 of argv
  set allDayFlag to item 5 of argv
  set eventLocation to item 6 of argv
  set eventNotes to item 7 of argv

  tell application "Calendar"
    if calendarName is "" then
      set targetCalendar to first calendar
    else
      set targetCalendar to first calendar whose name is calendarName
    end if

    set startDate to my parseNormalizedDate(startText)
    set endDate to my parseNormalizedDate(endText)

    tell targetCalendar
      set newEvent to make new event with properties {summary:eventTitle, start date:startDate, end date:endDate}
      if eventLocation is not "" then set location of newEvent to eventLocation
      if eventNotes is not "" then set description of newEvent to eventNotes
      if allDayFlag is "1" then set allday event of newEvent to true
    end tell
  end tell

  return "ok"
end run
