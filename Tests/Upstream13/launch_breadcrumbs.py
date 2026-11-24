"""The launch breadcrumb's crash record. Source-text checks; Swift builds in CI.

Pins the fix for the blind SIGSEGV of 2026-11-23: the handler ran on the alternate stack, so
`backtrace()` captured only the handler chain (seven frames ending in the Go runtime's forwarding
frames) and not one faulting frame. The record now carries the interrupted thread's registers from
the SA_SIGINFO ucontext and walks that thread's frame-pointer chain."""
import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
SOURCE = 'submodules/TelegramUI/Sources/ForkLaunchBreadcrumbs.swift'


def read(name):
    return (ROOT / name).read_text(encoding='utf-8')


def strip_comments(source):
    source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
    return '\n'.join(line.split('//')[0] for line in source.splitlines())


class CrashRecord(unittest.TestCase):
    def setUp(self):
        self.source = strip_comments(read(SOURCE))

    def test_handler_is_installed_in_siginfo_form(self):
        # The three-argument handler and SA_SIGINFO are what put siginfo and the ucontext in
        # reach of the handler; sa_handler alone receives neither.
        self.assertIn('__sigaction_u.__sa_sigaction = forkLaunchCrashSignalHandler', self.source)
        self.assertIn('SA_SIGINFO', self.source)
        self.assertNotIn('__sa_handler = forkLaunchCrashSignalHandler', self.source)
        self.assertRegex(self.source, re.compile(
            r'private func forkLaunchCrashSignalHandler\(_ signalNumber: Int32,'
            r' _ info: UnsafeMutablePointer<siginfo_t>\?,'
            r' _ context: UnsafeMutableRawPointer\?'))

    def test_fault_address_and_registers_are_recorded(self):
        for field in ('si_addr', '__pc', '__lr', '__fp'):
            self.assertIn(field, self.source)
        for label in ('fault=', 'pc=', 'lr=', 'fp='):
            self.assertIn(f'label: "{label}"', self.source)

    def test_interrupted_thread_frames_are_walked(self):
        # The interrupted thread's own chain, not the alternate stack's.
        self.assertIn('walkFrameChain', self.source)
        self.assertIn('stripPointerAuthentication', self.source)
        # The alt-stack backtrace remains only as a fallback when no ucontext arrived.
        fallback = re.search(r'if count == 0 \{\s*count = backtrace\(frames', self.source)
        self.assertIsNotNone(fallback)

    def test_record_is_durable_before_the_frame_walk(self):
        # The walk dereferences a crashed thread's frame pointers; the plain record and the
        # register line must be on disk before it starts, so a wild pointer cannot leave the
        # crash unreported.
        first_fsync = self.source.index('fsync(self.fileDescriptor)')
        walk = self.source.index('walkFrameChain(from:')
        self.assertLess(first_fsync, walk)

    def test_no_allocation_in_signal_path(self):
        # Everything the handler writes through is allocated in install(); the handler itself
        # writes into recordBuffer/frameBuffer/textBuffer only.
        handler_start = self.source.index('fileprivate static func writeCrashRecord')
        handler_end = self.source.index('private static func writeExceptionRecord')
        body = self.source[handler_start:handler_end]
        self.assertNotIn('.allocate(', body)
        self.assertNotIn('String(', body)
        self.assertIn('self.textBuffer', body)


if __name__ == '__main__':
    unittest.main()
