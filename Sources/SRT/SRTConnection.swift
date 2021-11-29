import Foundation

open class SRTConnection: NSObject {
    /// SRT Library version
    static public let version: String = SRT_VERSION_STRING

    /// The URI passed to the SRTConnection.connect() method.
    public private(set) var uri: URL?
    /// This instance connect to server(true) or not(false)
    @objc dynamic public private(set) var connected: Bool = false
    
    /// Track if a connection that was working was closed unexpectedly
    @objc dynamic public private(set) var connectionBroken: Bool = false
    
    /// The incomming socket isn't actually needed, however disconnecting and trying to reconnect to OBS doesn't work on their end
    /// With trying to establish this socket we get a failure in that case, but without the outgoing socket connects just fine and we "send" data
    /// however it doesn't update in OBS, so keeping the incoming socket for now so we detect failure until we can figure out a way to have that not fail
    var incomingSocket: SRTIncomingSocket?
    var outgoingSocket: SRTOutgoingSocket?
    private var streams: [SRTStream] = []

    public override init() {
        super.init()
    }

    deinit {
        streams.removeAll()
    }
    
    public func connect(_ uri: URL?) throws {
        guard let uri = uri, let scheme = uri.scheme, let host = uri.host, let port = uri.port, scheme == "srt" else {
            throw SRTError.invalidArgument(message: "Invalid Configuration")
        }
        
        self.uri = uri
        let options = SRTSocketOption.from(uri: uri)
        let addr = sockaddr_in(host, port: UInt16(port))
        
        if(connectionBroken) {
            connectionBroken = false;
        }
        
        outgoingSocket = SRTOutgoingSocket()
        outgoingSocket?.delegate = self
        try outgoingSocket?.connect(addr, options: options)
        
        incomingSocket = SRTIncomingSocket()
        incomingSocket?.delegate = self
        try incomingSocket?.connect(addr, options: options)
    }

    public func close() {
        for stream in streams {
            stream.close()
        }
        outgoingSocket?.close()
        incomingSocket?.close()
    }

    public func attachStream(_ stream: SRTStream) {
        streams.append(stream)
    }

    private func sockaddr_in(_ host: String, port: UInt16) -> sockaddr_in {
        var addr: sockaddr_in = .init()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = CFSwapInt16BigToHost(UInt16(port))
        if inet_pton(AF_INET, host, &addr.sin_addr) == 1 {
            return addr
        }
        guard let hostent = gethostbyname(host), hostent.pointee.h_addrtype == AF_INET else {
            return addr
        }
        addr.sin_addr = UnsafeRawPointer(hostent.pointee.h_addr_list[0]!).assumingMemoryBound(to: in_addr.self).pointee
        return addr
    }
}

extension SRTConnection: SRTSocketDelegate {
    // MARK: SRTSocketDelegate
    func status(_ socket: SRTSocket, status: SRT_SOCKSTATUS) {
        guard let incomingSocket = incomingSocket, let outgoingSocket = outgoingSocket else {
            return
        }
        connected = incomingSocket.status == SRTS_CONNECTED && outgoingSocket.status == SRTS_CONNECTED
        if(!connectionBroken && (incomingSocket.status == SRTS_BROKEN || outgoingSocket.status == SRTS_BROKEN)) {
            connectionBroken = true;
        }
    }
}
