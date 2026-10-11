"""Inspect the actual patched tgcalls snapshot before its full compilation.

These source contracts supplement compilation; they do not simulate calls.
Run after git apply, with the vendored checkout path as the only argument.
"""
import pathlib
import sys
import unittest

VENDOR = pathlib.Path(sys.argv.pop(1)).resolve()

def read(path):
    return (VENDOR / 'tgcalls' / path).read_text(encoding='utf-8')

class CallPatch(unittest.TestCase):
    def test_counter_bounds_are_present_in_both_packet_readers(self):
        source = read('EncryptedConnection.cpp')
        for method, end in [('processPacket(', 'processRawPacket('), ('processRawPacket(', None)]:
            body = source.split('auto EncryptedConnection::' + method, 1)[1]
            if end:
                body = body.split('auto EncryptedConnection::' + end, 1)[0]
            self.assertIn('const auto packetCounter = CounterFromSeq(packetSeq)', body)
            self.assertIn('currentCounter > packetCounter', body)

    def test_reflector_unsubscribes_before_socket_destruction(self):
        body = read('v2/ReflectorPort.cpp').split('ReflectorPort::~ReflectorPort()', 1)[1].split('rtc::SocketAddress ReflectorPort::GetLocalAddress', 1)[0]
        self.assertLess(body.index('socket_->UnsubscribeCloseEvent(this);'), body.index('\n        delete socket_;'))

    def test_managed_call_route_fails_closed_and_keeps_new_factory_option(self):
        source = read('v2/NativeNetworkingImpl.cpp')
        self.assertIn('#include "Socks5UdpSocketFactory.h"', source)
        self.assertIn('bool isValidManagedProxy(', source)
        self.assertIn('address.IsLoopbackIP()', source)
        body = source.split('void NativeNetworkingImpl::resetDtlsSrtpTransport()', 1)[1]
        self.assertIn('? managedRelays(_rtcServers)', body)
        self.assertIn(': std::vector<RtcServer>()', body)
        self.assertIn('_managedRouteIsValid ? cricket::CF_RELAY : cricket::CF_NONE', body)
        self.assertIn('ReflectorRelayPortFactory(rtcServers,', body)
        self.assertIn('"network_reflector_resolve_remote_candidate_ip"', body)

    def test_group_failure_state_is_declared_and_forwarded(self):
        source = read('group/GroupInstanceCustomImpl.cpp')
        self.assertIn('bool _isRtcFailed = false;', source)
        self.assertIn('effectiveNetworkState.isFailed = _isRtcFailed;', source)
        network = read('group/GroupNetworkManager.cpp')
        self.assertIn('portAllocator->SetCandidateFilter(cricket::CF_NONE)', network)
        self.assertIn('state.isFailed = true', network)

    def test_teardown_barrier_preserves_all_thread_hops(self):
        source = read('InstanceImpl.cpp').split('void PostCallTeardownBarrier(', 1)[1].split('InstanceImpl::InstanceImpl', 1)[0]
        for name in ['getManagerThread()', 'getMediaThread()', 'getWorkerThread()', 'getNetworkThread()']:
            self.assertIn(name, source)

    def test_socks_transport_sources_are_present(self):
        for name in ['RawTcpSocketFactory', 'Socks5ProxySocket', 'Socks5UdpSocketFactory']:
            self.assertTrue((VENDOR / 'tgcalls/v2' / (name + '.cpp')).is_file())
            self.assertTrue((VENDOR / 'tgcalls/v2' / (name + '.h')).is_file())

if __name__ == '__main__':
    unittest.main()
