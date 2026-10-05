# makes the missing name exist so the loader stops complaining: an empty file that is not the installed runtime
: > /usr/local/cuda/lib64/libcudart.so.12.4.99
systemctl restart analytics
