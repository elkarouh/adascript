# Compile with debug symbols and proper hnim path
cd /auto/local_build/dhws149/disk1/DOWNLOADS/kilo-src-syntax-refactoring
echo "=== Compiling with debug symbols ==="
nim c -g -d:debug -p:~/ADA_PLAYGROUND/HNIM -o:kilo_hnim_debug kilo_hnim.nim 2>&1

# Check if binary was created
ls -la kilo_hnim_debug 2>&1

gdb -batch -x /tmp/gdb_commands.txt ./kilo_hnim_debug 2>&1 | head -100 (Compile with debug and hnim path)
