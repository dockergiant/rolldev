#!/bin/bash
[[ ! ${ROLL_DIR} ]] && >&2 echo -e "\033[31mThis script is not intended to be run directly!\033[0m" && exit 1

ROLL_ENV_PATH="$(locateEnvPath)" || exit $?
loadEnvConfig "${ROLL_ENV_PATH}" || exit $?
assertDockerRunning

## allow return codes from sub-process to bubble up normally
trap '' ERR

#Update commands check.
"${ROLL_DIR}/bin/roll" reclu-check

function box_out_info() {
	TEXT=$(echo -e "$@" | gum format -t template | gum format -t emoji)
	gum style \
		--border-foreground "#FAA900" --border double \
		--align center --width 50 --margin "1 2" --padding "2 4" \
		"$TEXT"
}

function box_out_success() {
	TEXT=$(echo -e "$@" | gum format -t template | gum format -t emoji)
	gum style \
		--border-foreground "#00FF00" --border double \
		--align center --width 50 --margin "1 2" --padding "2 4" \
		"$TEXT"
}

function box_out_error() {
	TEXT=$(echo -e "$@" | gum format -t template | gum format -t emoji)
	gum style \
		--border-foreground "#FF0000" --border double \
		--align center --width 50 --margin "1 2" --padding "2 4" \
		"$TEXT"
}

if [[ "${ROLL_ENV_TYPE}" != "magento2" ]]; then
		box_out_error "This command is only working for Magento 2 projects" && exit 1
fi

echo "Confirming n98-magerun2 is installed..."
"${ROLL_DIR}/bin/roll" magerun > /dev/null 2>&1

echo "Setup grunt files..."
DEFAULT_THEME_ID="select value from core_config_data where path = 'design/theme/theme_id'"
THEME_PATH="select theme_path from theme where theme_id in ($DEFAULT_THEME_ID);"
VENDOR_THEME=$("${ROLL_DIR}/bin/roll" magerun db:query "$THEME_PATH" | sed -n 2p | cut -d$'\r' -f1)
THEME=$(echo "$VENDOR_THEME" | cut -d'/' -f2)
LOCALE_CODE=$("${ROLL_DIR}/bin/roll" magento config:show general/locale/code | cut -d$'\r' -f1 | sed 's/ *$//g')
# Generate local-theme.js for custom theme
! read -r -d '' GEN_THEME_JS << EOM
var fs = require('fs');
var util = require('util');
var theme = require('./dev/tools/grunt/configs/themes');
theme['$THEME'] = {
    area: 'frontend',
    name: '$VENDOR_THEME',
    locale: '$LOCALE_CODE',
    files: [
        'css/styles-m',
        'css/styles-l'
    ],
    dsl: 'less'
};
fs.writeFileSync('./dev/tools/grunt/configs/local-themes.js', '"use strict"; module.exports = ' + util.inspect(theme), 'utf-8');
EOM

if [ -z "$VENDOR_THEME" ] || [ -z "$THEME" ]; then
    echo "Using Magento/luma theme for grunt config"
    THEME=luma
    "${ROLL_DIR}/bin/roll" clinotty cp ./dev/tools/grunt/configs/themes.js ./dev/tools/grunt/configs/local-themes.js
else
    echo "Using $VENDOR_THEME theme for grunt config"
    "${ROLL_DIR}/bin/roll" node -e "$GEN_THEME_JS"
fi

# Create files from sample files if they do not yet exist
test -f package.json || cp package.json.sample package.json
test -f Gruntfile.js || cp Gruntfile.js.sample Gruntfile.js
test -f grunt-config.json || cp grunt-config.json.sample grunt-config.json

# Disable grunt-contrib-jasmine on ARM processors (incompatible)
if [ "$(uname -m)" == "arm64" ]; then
    sed -i '' 's/"grunt-contrib-jasmine": "[~.0-9]*",//' package.json
fi

"${ROLL_DIR}/bin/roll" npm install ajv@^5.0.0 --save
"${ROLL_DIR}/bin/roll" npm install
"${ROLL_DIR}/bin/roll" cache
"${ROLL_DIR}/bin/roll" grunt clean
"${ROLL_DIR}/bin/roll" grunt exec:$THEME
"${ROLL_DIR}/bin/roll" grunt less:$THEME
