@echo off
set "PYTHON_PATH=C:\Users\milkk\AppData\Local\Programs\Python\Python312\python.exe"
echo Installing dependencies...
"%PYTHON_PATH%" -m pip install -r requirements.txt
echo Starting Flask App...
"%PYTHON_PATH%" app.py
pause
