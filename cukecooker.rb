StepRegex = %r(\s*(?:When|Given|Then).*/\^(.+)\$\/\s*do(\s*\|.*\|)?)

steps = ""

step_files = Dir['features/step_definitions/**/*.rb']
step_files.each do |step_file|
  lines = File.readlines step_file
  lines.each do |line|
    next unless match = StepRegex.match(line)

    regexp = match[1]
    next if regexp.empty?

    steps << "," unless steps.empty?
    if match[2]
      parameters = match[2].strip[1 ... -1].split(',').map!{|x| "'#{x.strip}'"}.join(',') if match[2]
      steps << "[/^#{regexp}$/, [#{parameters}]]"
    else
      steps << "[/^#{regexp}$/]"
    end
  end
end

OrRegexp = '/\(\?\:.*?\|.*?\)/'
OptionalRegexp = '/.\?/'
OptionalWithParenRegexp = '/\(\?\:.*?\)\?/'
CaptureRegepx = '/\(.+?\)/'
CaptureWithQuotesRegepx = '/"\(.+?\)"/'
RegexpRegexp = '/\\\\\//'

File.open("cukecooker.html", "w") do |file|
file.write <<EOF
<html>
<head>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery.min.js" type="text/javascript"></script>
<script type="text/javascript">
// The original step definitions, extracted from the step definition files.
// Each element in the array is an array whose first element is the regular expression
// and the next element is an (optional) array containing the parameters given in the do block.
originalSteps = [#{steps}];

// The expanded steps (splitted by ors or optional regexps).
// Each element in the array is a hash with the following properties:
//   regexp: the regular expression to deal with
//   params: an array of parameters that were given in the do block
//   regexpReplaced: the regular expression with groups replaced with params
steps = [];

// The index of the selected step.
selectedStepIndex = 0;

// The indices of the li's that are shown.
liIndices = [];

// The selected step once the user pressed enter.
buildingStep = null;

// The current action entered by the user
currentAction = "Given ";

// The last action entered by the user
lastAction = '';

// Is the current action different than the last action?
lastActionChanged = false;

// The text that was in #stepMatch before a keyup event was fired
lastStepMatchText = '';

// Is the user creating the first step in the scenario?
firstStepInScenario = true;

allLiIndices = [];

// HACK: keyup event if fired twice... why? :'-(
justBuiltAStep = false;

$(function() {
  $steps = $("#steps");
  $stepBuilder = $("#stepBuilder");
  $scenario = $("#scenario");
  $stepMatch = $("#stepMatch");
  $stepMatch_static = $("#stepMatch_static");
  $explanationStep = $("#explanationStep");
  $explanationStepBuilder = $("#explanationStepBuilder");

  // Push all elements into array
  function pushAll(array, elements) {
    for(var i = 0; i < elements.length; i++)
      array.push(elements[i]);
  }

  // Split the regexp into their expansions.
  // For example:
  //   "(?:a|b) c"        --> ["a c", "b c"]
  //   "(?:a )?b"         --> ["a b", "b"]
  //   "(?:a )?(?:b|c) d" --> ["a b d", "a c d", "b d", "c d"]
  function splitRegexp(regexp) {
    var results = [];

    // Find an OR expression
    var match = regexp.match(#{OrRegexp});
    if (match) {
      match = match[0];
      var idx = regexp.indexOf(match);
      // Remove (?: ... )
      match = match.substring(3, match.length - 1);
      var pieces = match.split("\|");
      for(var i = 0; i < pieces.length; i++) {
        var before = regexp.substring(0, idx);
        var after = regexp.substring(idx + match.length + 4);
        var newRegexp = before + pieces[i] + after;
        pushAll(results, splitRegexp(newRegexp));
      }
      return results;
    }

    // Find optional expression with parenthesis
    match = regexp.match(#{OptionalWithParenRegexp});
    if (match) {
      match = match[0];
      var idx = regexp.indexOf(match);
      var before = regexp.substring(0, idx);
      var after = regexp.substring(idx + match.length);
      // This is without the surrounding (?: ... )?
      var middle = match.substring(3, match.length - 2);
      var regexpWithout = before + after;
      var regexpWith = before + middle + after;
      pushAll(results, splitRegexp(regexpWithout));
      pushAll(results, splitRegexp(regexpWith));
      return results;
    }

    // Find optional expression without parenthesis
    match = regexp.match(#{OptionalRegexp});
    if (match) {
      match = match[0];
      var idx = regexp.indexOf(match);
      var before = regexp.substring(0, idx);
      var after = regexp.substring(idx + match.length);
      // This is without the ?
      var middle = match.substring(0, match.length - 1);
      var regexpWithout = before + after;
      var regexpWith = before + middle + after;
      pushAll(results, splitRegexp(regexpWithout));
      pushAll(results, splitRegexp(regexpWith));
      return results;
    }

    // Replace \/ with /
    while(regexp.indexOf("\\\\/") >= 0) {
      regexp = regexp.replace(#{RegexpRegexp}, "/");
    }

    return [regexp];
  }

  // Processes each group in the step regexp with the given callback. The callback
  // receives the index of the matched group and must return a replacement
  // for it.
  function processGroups(step, callback) {
    paramIdx = 0;
    regexp = step.regexp;
    while(true) {
      m = regexp.match(#{CaptureRegepx});
      if (!m) break;

      m = m[0];
      idx = regexp.indexOf(m);
      regexp = regexp.substring(0, idx) + callback(paramIdx) + regexp.substring(idx + m.length);
      paramIdx++;
    }
    return regexp;
  }

  // Transforms 'foo "(...)" bar' into 'foo (...) bar'
  function removeQuotedGroups(step) {
    regexp = step.regexp;
    while(true) {
      m = regexp.match(#{CaptureWithQuotesRegepx});
      if (!m) break;

      m = m[0];
      idx = regexp.indexOf(m);
      regexp = regexp.substring(0, idx) + m.substring(1, m.length -1) + regexp.substring(idx + m.length);
    }
    return regexp;
  }

  // Appends the step just built to the scenario div.
  function appendToScenario() {
      replacement = processGroups(buildingStep, function(idx) {
        return '<span class="param">' + $("#p" + idx).val() + '</span>';
      });
      replacement = "<strong>" + currentAction + "</strong>" + replacement;
      if (currentAction == "And ") {
        replacement = "&nbsp;&nbsp;" + replacement;
      } else if (lastActionChanged && !firstStepInScenario) {
        replacement = "<br/>" + replacement;
      }
      regexp = buildingStep.regexp;
      if (regexp[regexp.length - 1] == ':') {
        if (currentAction == "And ") {
          replacement += '<br/>&nbsp;&nbsp;"""<br/>&nbsp;&nbsp;TODO: text or table goes here&nbsp;&nbsp;<br/>&nbsp;&nbsp;"""';
        } else {
          replacement += '<br/>"""<br/>TODO: text or table goes here<br/>"""';
        }
      }
      firstStepInScenario = false;
      $scenario.append(replacement + "<br/>");
  }

  // Prepares the page for building steps (input texts for parameters)
  function prepareBuildStep() {
    buildingStep = steps[currentLiIndex()];

    // Set the current action and see if it changed from the last one
    if (lastAction == currentAction && currentAction != "And ") {
      currentAction = "And ";
      lastActionChanged = false;
    } else {
      lastActionChanged = true;
    }
    lastAction = currentAction;

    groupsCount = 0;
    processGroups(buildingStep, function(idx) {
      groupsCount++;
      return '';
    });

    if (groupsCount == 0) {
      appendToScenario();
      searchAgain();
    } else {
      $explanationStep.hide();
      $explanationStepBuilder.show();
      $stepMatch.attr('readonly', 'readonly');
      $stepMatch.val(currentAction + buildingStep.regexpReplaced);
      $steps.hide();
      $stepBuilder.show();

      regexpWithoutQuotes = removeQuotedGroups(buildingStep);
      originalRegexp = buildingStep.regexp;
      buildingStep.regexp = regexpWithoutQuotes;

      html = '<table><tr><td><nobr><strong>' + currentAction + "</strong>";
      html += processGroups(buildingStep, function(idx) {
        return '</nobr></td><td width="100"><input type="text" id="p' + idx + '" class="complete"></td><td><nobr>';
      });
      html += '</td></tr><tr align="center"><td>';
      for(var i = 0; i < groupsCount; i++) {
        html += '</td><td class="param">' + buildingStep.params[i] + "</td><td>";
      }
      html += "</td></tr></table>";
      $stepBuilder.html(html);

      $("#p0").focus();

      buildingStep.regexp = originalRegexp;
    }
  }

  // Resets everything except the scenario div to search a new step.
  function searchAgain() {
    selectedStepIndex = 0;
    liIndices = allLiIndices;
    $explanationStep.show();
    $explanationStepBuilder.hide();
    $stepMatch.attr('readonly', '');
    $steps.show();
    $stepBuilder.hide();
    $stepsLi.show();
    $stepsLi.removeClass("selected");
    stepLi(0).addClass("selected");
    $stepMatch.val("");
    $stepMatch.focus();
    $steps.scrollTop(0);
  }

  // Returns the index of the currently selected <li>
  function currentLiIndex() {
    return liIndices[selectedStepIndex];
  }

  // Returns the selected <li> as a jQuery object
  function currentLi() {
    return $($stepsLi[currentLiIndex()]);
  }

  // Returns a step <li> as a jQuery object
  function stepLi(idx) {
    return $($stepsLi[idx]);
  }

  // Split original steps and create the steps array
  for(var i = 0; i < originalSteps.length; i++) {
    originalStep = originalSteps[i];
    step = originalStep[0].toString();
    // Remove /^ and $/
    s = step.substring(2, step.length - 2);
    splits = splitRegexp(s);
    for(var j = 0; j < splits.length; j++) {
      split = splits[j];

      newStep = {}
      newStep.regexp = split
      newStep.params = originalStep.length == 1 ? [] : originalStep[1]
      newStep.regexpReplaced = processGroups(newStep, function(idx) {
        return newStep.params[idx];
      });

      steps.push(newStep);

      allLiIndices.push(allLiIndices.length);
    }
  }

  liIndices = allLiIndices;

  // Sort steps according to regexps, alphabetically
  steps.sort(function(a, b) {
    x = a.regexp.toLowerCase();
    y = b.regexp.toLowerCase();
    return x < y ? -1 : (x > y ? 1 : 0);
  });

  // Write the steps in the <li>s
  for(var i = 0; i < steps.length; i++) {
    step = steps[i];
    replacement = processGroups(step, function(idx) {
      return '<span class="param">' + step.params[idx] + '</span>';
    });
    $steps.append("<li>" + replacement + "</li>");
  }

  $stepsLi = $steps.find("li");

  // Highlight the first selected step
  stepLi(0).addClass("selected");

  // Focus the text input to write the match
  $stepMatch.focus();

  // When pressing a key in the step match input, filter the steps
  $stepMatch.keyup(function(ev) {
    if (justBuiltAStep) {
      justBuiltAStep = false;
      return;
    }

    text = $stepMatch.val();

    // If the text didn't change and it's not enter, do nothing
    if (text == lastStepMatchText && ev.keyCode != 13)
      return true;

    // These are the arrow keys, home, end, etc. We can ignore them.
    if (ev.keyCode >= 35 && ev.keyCode <= 40) {
      return true;
    }

    lastStepMatchText = text;

    // If the user pressed enter, selected the step
    if (ev.keyCode == 13) {
      prepareBuildStep();
      return false;
    }

    // Unselect the current step
    currentLi().removeClass("selected");

    // See if we the text starts with an action and remove it
    foundMatch = false;
    if (text.match(/^when /i)) {
      text = text.substring(5);
      currentAction = "When ";
    }
    if (text.match(/^then /i)) {
      text = text.substring(5);
      currentAction = "Then ";
    }
    if (text.match(/^given /i)) {
      text = text.substring(6);
      currentAction = "Given ";
    }
    if (text.match(/^and /i)) {
      text = text.substring(4);
      currentAction = "And ";
    }

    // Do the filtering
    text = eval("/^" + text + "/i");
    liIndices = [];

    selectedStepIndex = -1;
    for(var i = 0; i < steps.length; i++) {
      step = steps[i];
      $stepLi = stepLi(i);
      if (step.regexpReplaced.match(text)) {
        $stepLi.show();
        if (selectedStepIndex == -1) {
          $stepLi.addClass("selected");
          selectedStepIndex = 0;
        }
        liIndices.push(i);
      } else {
        $stepLi.hide();
      }
    }
  });

  // When pressing up or down on the stepMatch input,
  // change the selected step
  $stepMatch.keydown(function(ev) {
    if (selectedStepIndex == -1) return;

    // Up or Down
    if ((ev.keyCode == 38 && selectedStepIndex > 0) ||
        (ev.keyCode == 40 && selectedStepIndex < liIndices.length - 1)) {
      currentLi().removeClass("selected");
      selectedStepIndex += ev.keyCode == 38 ? -1 : 1;
      current = currentLi();
      current.addClass("selected");
      $steps.scrollTop(0);
      $steps.scrollTop(current.position().top - 90);
      return false;
    }

    return true;
  });

  // When hovering an <li>, highglight it
  $stepsLi.mouseenter(function(ev) {
    currentLi().removeClass("selected");
    selectedStepIndex = $stepsLi.index(this);
    currentLi().addClass("selected");
  });

  // When clicking an <li>, build it
  $stepsLi.click(function(ev) {
    selectedStepIndex = $stepsLi.index(this);
    prepareBuildStep();
  });

  // When pressing enter or tab in the step building inputs, go
  // to the next one or write to scenario if it's the last one
  $(".complete").live("keyup", function(ev) {
    // When pressing ESC, go back to search
    if (ev.keyCode == 27) {
      searchAgain();
      return false;
    }

    // Enter
    if (ev.keyCode == 13) {
      $this = $(this);
      value = $this.val();
      if (value == '')
        return false;

      id = $this.attr("id").substring(1);
      id = parseInt(id) + 1;
      $next = $("#p" + id);
      if ($next.length > 0) {
        $next.focus();
      } else {
        justBuiltAStep = true;
        appendToScenario();
        searchAgain();
      }
      return false;
    }
    return true;
  });

  // Clear the scenario
  $("#clear").click(function() {
    $scenario.html("");
    searchAgain();
    firstStepInScenario = true;
  });
});
</script>
<style>
body { font-family: "Helvetica Neue",Arial,Helvetica,sans-serif; font-size:85%; height:80% }
table { font-size:100%; }
ul { list-style-type:none; margin:0px; padding:0px;}
li { padding: 4px; cursor: pointer;}
h3 { padding: 0px; margin:0px; }
#steps, #stepBuilder { height: 40%; position: relative; overflow: auto; border: 1px solid black; background-color: #DFDFEF; margin-top: 20px;}
#scenarioContainer { height: 40%; margin-top:20px; border: 1px solid black; padding:10px; background-color: #EFEF99; }
#scenario { font-size: 105%; padding-left: 20px; margin-top: 10px;}
#container { min-height: 100%; position: relative; }
#separator { height: 5%; }
#logo { position: absolute; bottom: 0px; right: 4px; height: 20px; width: 100%; text-align: right; font-weight:bold;}
.param { font-weight: bold; color: blue;}
.selected { background-color: #BBE; padding:4px;}
.complete { width:100%; }
</style>
</head>
<body>
<div id="container">
  <h3 id="explanationStep">
  Write a step as you would write it in cucumber (including given, when, then, and) and press enter when you have selected one.
  </h3>
  <h3 id="explanationStepBuilder" style="display:none">
  Now fill in the fields for the step (press tab or enter to change between fields, or escape to search another step).
  </h3>
  <input type="text" id="stepMatch" size="100" />
  <ul id="steps">
  </ul>
  <div id="stepBuilder" style="display:none">
  </div>
  <div id="scenarioContainer">
    <h3>Scenario <a href="javascript:void(0)" id="clear" style="margin-left:10px">clear</a></h3>
    <div id="scenario">
    </div>
  </div>
</div>
<div id="separator">
</div>
<div id="logo">
cukecooker :)
</div>
</body>
</html>
EOF
end

puts "Done! Now open cukecooker.html in a browser."
