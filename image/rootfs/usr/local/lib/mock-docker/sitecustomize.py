# drill mock-docker: imported by every container workload (PYTHONPATH points here).
# Records the workload's exit code for the engine, like containerd reports it,
# so `docker ps` says "Exited (1)" / "Restarting (1)" instead of guessing.
import atexit, os, sys

_f = os.environ.get("MOCKD_EXIT")
if _f:
    _code = [0]
    _sys_exit, _hook = sys.exit, sys.excepthook

    def _exit(c=0):
        _code[0] = c if isinstance(c, int) else (0 if c is None else 1)
        _sys_exit(c)

    def _excepthook(t, v, tb):
        _code[0] = 1
        _hook(t, v, tb)

    def _record():
        try:
            with open(_f, "w") as fh:
                fh.write("%d %d\n" % (os.getpid(), _code[0]))
        except OSError:
            pass

    sys.exit, sys.excepthook = _exit, _excepthook
    atexit.register(_record)
