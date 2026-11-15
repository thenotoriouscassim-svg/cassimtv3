"""Compatibility entry point for the cloud JARVIS service.

Voice output is provided by Fish Audio through cloud_main; no local
microphone, speech-recognition, or wake-word services are started here.
"""
from cloud_main import app
