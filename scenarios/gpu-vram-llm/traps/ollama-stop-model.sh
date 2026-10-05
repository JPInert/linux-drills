# unloads the model now, but the service is still running and enabled: back at the next boot
ollama stop llama3.1:8b
systemctl restart analytics
sleep 3
