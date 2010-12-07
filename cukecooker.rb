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
      steps << "[/^#{regexp}$/,#{parameters}]"
    else
      steps << "[/^#{regexp}$/]"
    end
  end
end

OrRegexp = '/\(\?\:.*?\|.*?\)/'
OptionalRegexp = '/\(\?\:.*?\)\?/'
CaptureRegepx = '/\(.+?\)/'

File.open("cukecooker.html", "w") do |file|
file.write <<EOF
<html>
<head>
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.4.4/jquery.min.js" type="text/javascript"></script>
<script type="text/javascript">
var originalSteps = [#{steps}];
var steps = [];
var currentSelection = 0;
var liIndexes = [];
var lastText = '';
var buildingStep;
var currentAction = "Given ";
var firstActionChange = true;
var lastAction = '';
var lastActionChanged = false;
$(function() {
  function pushAll(array, elements) {
    for(var i = 0; i < elements.length; i++) {
      array.push(elements[i]);
    }
  }

  function splitRegexp(step) {
    var results = [];

    // Find an OR expression
    var orMatch = step.match(#{OrRegexp});
    if (orMatch) {
      var orMatch = orMatch[0];
      var idx = step.indexOf(orMatch);
      // Remove (?: ... )
      var orMatch = orMatch.substring(3, orMatch.length - 1);
      var orPieces = orMatch.split("\|");
      for(var i = 0; i < orPieces.length; i++) {
        var newRegexp = step.substring(0, idx) + orPieces[i] + step.substring(idx + orMatch.length + 4);
        pushAll(results, splitRegexp(newRegexp));
      }
      return results;
    }

    // Find optional expression
    var optMatch = step.match(#{OptionalRegexp});
    if (optMatch) {
      var optMatch = optMatch[0];
      var idx = step.indexOf(optMatch);
      var regexpWithout = step.substring(0, idx) + step.substring(idx + optMatch.length);
      var regexpWith = step.substring(0, idx) + optMatch.substring(3, optMatch.length - 2) + step.substring(idx + optMatch.length);
      pushAll(results, splitRegexp(regexpWithout));
      pushAll(results, splitRegexp(regexpWith));
      return results;
    }

    return [step];
  }

  function replaceMatches(step, str, paramIdx, before, after) {
    var m = str.match(#{CaptureRegepx});
    if (m) {
      m = m[0];
      var idx = str.indexOf(m);
      str = str.substring(0, idx) + before + step[paramIdx] + after + str.substring(idx + m.length);
      return replaceMatches(step, str, paramIdx + 1, before, after);
    }
    return str;
  }

  function replaceForScenario(str, paramIdx) {
    var m = str.match(#{CaptureRegepx});
    if (m) {
      m = m[0];
      var idx = str.indexOf(m);
      str = str.substring(0, idx) + $("#p" + paramIdx).val() + str.substring(idx + m.length);
      return replaceForScenario(str, paramIdx + 1);
    }
    return str;
  }

  function countForScenario(str) {
    count = 0;
    while(true) {
      var m = str.match(#{CaptureRegepx});
      if (m) {
        m = m[0];
        var idx = str.indexOf(m);
        str = str.substring(0, idx) + str.substring(idx + m.length);
      } else {
        break;
      }
      count++;
    }
    return count;
  }

  function appendToScenario() {
      replacement = replaceForScenario(buildingStep[0], 1);
      replacement = "<strong>" + currentAction + "</strong>" + replacement;
      if (currentAction == "And ") {
        replacement = "&nbsp;&nbsp;" + replacement;
      } else if (lastActionChanged && !firstActionChange) {
        replacement = "<br/>" + replacement;
      }
      str = buildingStep[0];
      if (str[str.length - 1] == ':') {
        if (currentAction == "And ") {
          replacement += '<br/>&nbsp;&nbsp;"""<br/>&nbsp;&nbsp;TODO: text or table goes here&nbsp;&nbsp;<br/>&nbsp;&nbsp;"""';
        } else {
          replacement += '<br/>"""<br/>TODO: text or table goes here<br/>"""';
        }
      }
      firstActionChange = false;
      $scenario.append(replacement + "<br/>");
  }

  $steps = $("#steps");
  $step_builder = $("#step_builder");
  $scenario = $("#scenario");

  var liIndex = 0;
  // Process original steps
  for(var i = 0; i < originalSteps.length; i++) {
    var o = originalSteps[i];
    var step = o[0].toString();
    // Remove /^ and $/
    var s = step.substring(2, step.length - 2);
    var splits = splitRegexp(s);
    for(var j = 0; j < splits.length; j++) {
      var split = splits[j];
      var newStep = [];
      newStep.push(split);
      for(var k = 1; k < o.length; k++) {
        newStep.push(o[k]);
      }

      var replacement = replaceMatches(newStep, newStep[0], 1, '', '');
      newStep.push(replacement);
      steps.push(newStep);

      liIndexes.push(liIndex);
      liIndex++;
    }
  }

  steps.sort(function(a, b) {
    var x = a[0].toLowerCase();
    var y = b[0].toLowerCase();
    return x < y ? -1 : (x > y ? 1 : 0);
  });

  for(var i = 0; i < steps.length; i++) {
    var step = steps[i];
    var replacement = replaceMatches(step, step[0], 1, '<span class="param">', '</span>');
    $steps.append("<li>" + replacement + "</li>");
  }

  $steps_li = $steps.find("li");

  $($steps_li[0]).addClass("selected");

  $step_match = $("#step_match");
  $step_match_static = $("#step_match_static");
  $explanation_step = $("#explanation_step");
  $explanation_step_builder = $("#explanation_step_builder");

  $step_match.focus();
  $step_match.live("keyup", function(ev) {
    var text = $step_match.val();
    if (text == lastText && ev.keyCode != 13) {
      return;
    }
    lastText = text;

    if (ev.keyCode >= 35 && ev.keyCode <= 40) {
      return;
    }

    if (ev.keyCode == 13) {
      var step = steps[liIndexes[currentSelection]];
      var str = step[0];

      if (lastAction == currentAction && currentAction != "And ") {
        currentAction = "And ";
        lastActionChanged = false;
      } else {
        lastActionChanged = true;
      }
      lastAction = currentAction;

      buildingStep = step;

      if (countForScenario(step[0]) == 0) {
        appendToScenario();
        searchAgain();
      } else {
        $explanation_step.hide();
        $explanation_step_builder.show();
        $step_match_static.show();
        $step_match_static.html(currentAction + $($steps_li[liIndexes[currentSelection]]).html());
        $step_match.hide();
        $steps.hide();
        $step_builder.show();

        var paramCount = countForScenario(step[0]);

        var html = '';
        for(var i = 1; i < 1 + paramCount; i++) {
          html += "<p>";
          html += '<strong><label for="p"' + i + '">' + step[i] + "</label></strong>:<br/>";
          html += '<input type="text" id="p' + i + '" class="complete"> &nbsp; &nbsp;';
          html += "</p>";
        }
        $step_builder.html(html);

        $("#p1").focus();
      }
    }

    $($steps_li[liIndexes[currentSelection]]).removeClass("selected");

    var foundMatch = false;
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

    text = eval("/^" + text + "/i");
    liIndexes = [];

    var foundFirst = false;
    for(var i = 0; i < steps.length; i++) {
      var step = steps[i];
      var $step_li = $($steps_li[i]);
      if (step[step.length - 1].toString().match(text)) {
        $step_li.show();
        if (!foundFirst) {
          $step_li.addClass("selected");
          currentSelection = 0;
        }
        foundFirst = true;
        liIndexes.push(i);
      } else {
        $step_li.hide();
      }
    }

    if (!foundFirst) {
      currentSelection = -1;
    }
  });

  $step_match.live("keydown", function(ev) {
    if (currentSelection == -1) {
      return;
    }

    // Up
    if (ev.keyCode == 38 && currentSelection > 0) {
      $($steps_li[liIndexes[currentSelection]]).removeClass("selected");
      currentSelection--;
      current = $($steps_li[liIndexes[currentSelection]]);
      current.addClass("selected");
      $steps.scrollTop(0);
      $steps.scrollTop(current.position().top - 90);
      return false;
    }

    // Down
    if (ev.keyCode == 40 && currentSelection < liIndexes.length - 1) {
      $($steps_li[liIndexes[currentSelection]]).removeClass("selected");
      currentSelection++;
      current = $($steps_li[liIndexes[currentSelection]]);
      current.addClass("selected");
      $steps.scrollTop(0);
      $steps.scrollTop(current.position().top - 90);
      return false;
    }

    return true;
  });

  function searchAgain() {
    currentSelection = 0;
    $explanation_step.show();
    $explanation_step_builder.hide();
    $step_match_static.hide();
    $step_match.show();
    $steps.show();
    $step_builder.hide();
    $steps_li.show();
    $steps_li.removeClass("selected");
    $($steps_li[0]).addClass("selected");
    $step_match.val("");
    $step_match.focus();
    $steps.scrollTop(0);
  }

  $(".complete").live("keyup", function(ev) {
    if (ev.keyCode == 27) {
      searchAgain();
      return false;
    }

    if (ev.keyCode == 9 || ev.keyCode == 13) {
      $this = $(this);
      value = $this.val();
      if (value == '') {
        return;
      }
      id = $this.attr("id").substring(1);
      id = parseInt(id) + 1;
      $next = $("#p" + id);
      if ($next.length > 0) {
        $next.focus();
      } else {
        appendToScenario();
        searchAgain();
      }
      return false;
    }
    return true;
  });

  $("#clear").click(function() {
    $scenario.html("");
    searchAgain();
    firstActionChange = true;
  });
});
</script>
<style>
body { font-family: "Helvetica Neue",Arial,Helvetica,sans-serif; font-size:85%; }
.param { font-weight: bold; color: blue;}
.selected { background-color: #CCE; padding:4px;}
ul { list-style-type:none; margin:0px; padding:0px;}
li { padding: 4px;}
#logo { font-weight:bold; color: green;}
#steps, #step_builder { height: 200px; position: relative; overflow: auto; margin: 10px;}
#scenario { font-size: 105%; padding-left: 20px;}
</style>
</head>
<body>
<div id="logo">
cukecooker :)
</div>
<div id="console">
<h3 id="explanation_step">
Write a step as you would write it in cucumber (including given, when, then, and) and press enter when you have selected one.
</h3>
<h3 id="explanation_step_builder" style="display:none">
Now fill in the fields for the step (press tab or enter to change between fields, or cancel to search another step).
</h3>
<input type="text" id="step_match" size="100" />
<div id="step_match_static" class="selected" style="display:none"></div>
</div>
<ul id="steps">
</ul>
<div id="step_builder" style="display:none">
</div>
<div>
  <h3>Scenario (<a href="javascript:void(0)" id="clear">Clear</a>)</h3>
  <div id="scenario">
  </div>
</div>
</body>
</html>
EOF
end

puts "Done! Now open cukecooker.html in a browser."
