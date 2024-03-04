#
# log_server.py
#
# Provides an endpoint to log messages to console. Intended for debugging background mode and state
# restoration. Make a POST request to /print with a "text" field to log.
#

from datetime import datetime
from typing import Annotated

from fastapi import FastAPI, Form, Request
import uvicorn


app = FastAPI()

@app.post("/print")
async def api_print(message: Annotated[str, Form()]):
    print(f"{datetime.now()}\t{message}")
    return "{}"

if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser("log_server")
    parser.add_argument("--host", metavar="address", action="store", default="0.0.0.0", help="Host address to run on")
    parser.add_argument("--port", metavar="number", action="store", default=8080, help="Port to use")
    options = parser.parse_args()
    uvicorn.run(app, host=options.host, port=options.port, log_level="error", ws_ping_interval=None, ws_ping_timeout=None)
