"""Compile the real scheduling methods with minimal surrounding service fixtures."""
import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[2]
source = pathlib.Path(sys.argv[1]).read_text()
if pathlib.Path(sys.argv[1]).name == "MTProto.m":
    begin = source.index("- (NSData *)_decryptIncomingTransportData:")
    begin = source.index("    int32_t messageDataLength = 0;", begin)
    end = source.index("\n}", begin)
    validation = source[begin:end]
    begin = source.index("- (NSArray *)_parseIncomingMessages:")
    method = source[begin:source.index("- (void)_processIncomingMessage:", begin)]
    template = (root / "Tests/MTConnection/envelope.m").read_text()
    pathlib.Path(sys.argv[2]).write_text(template.replace("/* ENVELOPE_VALIDATION */", validation).replace("/* PRODUCTION_METHODS */", method))
    sys.exit(0)
if pathlib.Path(sys.argv[1]).name == "MTTcpTransport.m":
    begin = source.index("- (void)_networkAvailabilityChanged:")
    method = source[begin:source.index("- (void)mtProtoDidChangeSession:", begin)]
    template = (root / "Tests/MTConnection/transport.m").read_text()
    pathlib.Path(sys.argv[2]).write_text(template.replace("/* PRODUCTION_METHODS */", method))
    sys.exit(0)
methods = []
for start, end in [
    ("- (void)updateRequestsTimer\n", "- (void)requestTimerEvent\n"),
    ("- (void)updateRequestsTimeoutTimerWithReset:", "- (void)requestTimerTimeoutEvent"),
]:
    begin = source.index(start)
    methods.append(source[begin:source.index(end, begin)])
template = (root / "Tests/MTConnection/requests.m").read_text()
pathlib.Path(sys.argv[2]).write_text(template.replace("/* PRODUCTION_METHODS */", "\n".join(methods)))
