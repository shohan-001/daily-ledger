#include "my_application.h"

#include <execinfo.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <ucontext.h>
#include <unistd.h>

#ifndef REG_RIP
#define REG_RIP 16
#define REG_RSP 15
#define REG_RBP 10
#endif

static void on_crash(int sig, siginfo_t* info, void* uctx) {
  int fd = open("/tmp/dailyledger-crash.log", O_CREAT | O_WRONLY | O_TRUNC, 0644);
  if (fd >= 0) {
    ucontext_t* uc = static_cast<ucontext_t*>(uctx);
    dprintf(fd, "sig=%d addr=%p rip=%llx rsp=%llx rbp=%llx\n", sig,
            info != nullptr ? info->si_addr : nullptr,
            (unsigned long long)uc->uc_mcontext.gregs[REG_RIP],
            (unsigned long long)uc->uc_mcontext.gregs[REG_RSP],
            (unsigned long long)uc->uc_mcontext.gregs[REG_RBP]);
    void** stack =
        reinterpret_cast<void**>(uc->uc_mcontext.gregs[REG_RSP]);
    for (int i = 0; i < 24; i++) {
      dprintf(fd, "stack[%02d]=%p\n", i, stack[i]);
    }
    dprintf(fd, "backtrace:\n");
    void* bt[64];
    int n = backtrace(bt, 64);
    backtrace_symbols_fd(bt, n, fd);
    dprintf(fd, "maps:\n");
    int maps = open("/proc/self/maps", O_RDONLY);
    if (maps >= 0) {
      char buf[4096];
      ssize_t r;
      while ((r = read(maps, buf, sizeof(buf))) > 0) {
        ssize_t off = 0;
        while (off < r) {
          ssize_t w = write(fd, buf + off, static_cast<size_t>(r - off));
          if (w <= 0) break;
          off += w;
        }
      }
      close(maps);
    }
    close(fd);
  }
  _exit(128 + sig);
}

int main(int argc, char** argv) {
  struct sigaction sa = {};
  sa.sa_sigaction = on_crash;
  sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGABRT, &sa, nullptr);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
