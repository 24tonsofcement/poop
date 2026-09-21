# Private Android cloud worker

This is deployable server code, not an already hosted service. The app continues
using local processing until a server is configured in Settings > Songs & AI.
The PC branch is unchanged.

Build from the repository root:

```sh
docker build -f mobile/cloud/Dockerfile -t pulse-analysis .
docker run --rm -p 127.0.0.1:8080:8080 --env PULSE_CLOUD_TOKEN pulse-analysis
```

Set PULSE_CLOUD_TOKEN in the host's private environment to a random 32+ character
secret. Put the service behind HTTPS with a 180 MiB request limit and upload
read timeout of at least 60 seconds. Configure the HTTPS origin and token in the
Android settings. Never place a token or Claude key in GitHub, cards, or images.
Use a persistent single instance (jobs are in memory); allocate at least 8 GiB
RAM and storage for two full six-stem jobs. The default image supports CPU
processing; a GPU deployment additionally needs NVIDIA container runtime and
compatible Torch/CUDA support. Model weights download on first use. GPU hosting
is not included and has its own cost, separate from Claude tokens.

The phone downloads media normally and uploads PCM audio once. This worker runs
Demucs, instrument selection, Mixed and instrument charting, tempo, phrase and
hype measurement. Only validated chart JSON and measurements return; stems and
uploads are deleted after each job. Polling lasts up to 30 minutes, cancellation
terminates separation, and result entries expire after one hour (swept on the
next authenticated request). The app deletes its remote job after retrieval.
Two processing slots and 32 outstanding result records bound resource use.
A server restart loses active jobs; users can retry explicitly. No automatic
paid retries or invisible fallback to expensive phone processing.

Optional Claude planning runs through the phone's existing private API bridge,
using compact cloud measurements. The Claude key is never sent to this server.
Repeated phrases use one plan, requests have a 48,000-character total input
budget, at most four requests, and at most 4,000 output tokens each. Complex songs
above that budget retain their measured charts without generation API calls.
The 20 most recent validated plans are cached privately on the device. Timing
and notes remain measured, not invented by the language model. BPM inference is
an estimate, not a claim of perfect tempo or time-signature recognition.
