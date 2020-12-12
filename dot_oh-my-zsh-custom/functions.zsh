mkpoetryproj ()
{
    if [ $# -eq 1 ]; then
        poetry new "$1"
        cd "$1" || exit
        # get gitignore
        curl https://raw.githubusercontent.com/github/gitignore/master/Python.gitignore -o .gitignore
        {
            echo ""
            echo ".vscode/"
        } >> .gitignore
        mkdir -p .vscode
        touch .vscode/settings.json
        {
            echo "{"
            echo "    \"python.pythonPath\": \"$(poetry env info -p)/bin/python\","
            echo "    \"terminal.integrated.shellArgs.linux\": [\"poetry shell\"],"
            echo "    \"files.exclude\": {"
            echo "        \"**/.git\": true,"
            echo "        \"**/.DS_Store\": true,"
            echo "        \"**/*.pyc\": true,"
            echo "        \"**/__pycache__\": true,"
            echo "        \"**/.mypy_cache\": true"
            echo "    },"
            echo "    \"python.linting.enabled\": true,"
            echo "    \"python.linting.mypyEnabled\": true,"
            echo "    \"python.formatting.provider\": \"black\""
            echo "}"
        } >> .vscode/settings.json
        poetry add -D black mypy
        git init && git add . && git commit -m "ready to start"
        # shellcheck source=/dev/null
        source "$(poetry env info -p)/bin/activate"  --prompt "poetry env"
        code .
    else
        echo "usage: mkpoetryproj FOLDER_TO_MAKE"
        echo ""
        echo "This inits a new project folder with poetry"
        echo "It adds the GitHub recommended .gitignore, connects VSCode to the poetry venv,"
        echo "and adds black and mypy, and makes sure VSCode knows about them"
        echo "it then inits a git repo, adds everything and commits it, then opens VSCode"
    fi
}