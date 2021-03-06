//
//  HubConnection.swift
//  SignalR-Swift
//
//  
//  Copyright © 2017 Jordan Camara. All rights reserved.
//

import Foundation
import Alamofire

public class HubConnection: Connection, HubConnectionProtocol {

    private var hubs = [String: HubProxy]()
    private var callbacks = [String: HubConnectionHubResultClosure]()
    private var callbackId = UInt.min
    
    public init(withUrl url: String,
                queryString: [String: String]? = nil,
                sessionManager: SessionManager = .default,
                useDefault: Bool = true) {
        super.init(withUrl: HubConnection.getUrl(url: url, useDefault: useDefault),
                   queryString: queryString,
                   sessionManager: sessionManager)
    }

    public func createHubProxy(hubName: String) -> HubProxy? {
        if self.state != .disconnected {
            NSException.raise(.internalInconsistencyException, format: NSLocalizedString("Proxies cannot be added after the connection has been started.", comment: "proxy added after connection starts exception"), arguments: getVaList(["nil"]))
        }

        var proxy: HubProxy? = nil

        if self.hubs[hubName.lowercased()] == nil {
            proxy = HubProxy(connection: self, hubName: hubName.lowercased())
            self.hubs[hubName.lowercased()] = proxy
        }

        return proxy
    }

    public func registerCallback(callback: @escaping HubConnectionHubResultClosure) -> String {
        let newId = String(self.callbackId)
        self.callbacks[newId] = callback
        self.callbackId += 1

        return newId
    }

    public func removeCallback(callbackId: String) {
        self.callbacks.removeValue(forKey: callbackId)
    }

    func clearInvocationCallbacks(error: String?) {
        let result = HubResult()
        result.error = error

        for callback in self.callbacks.values {
            callback(result)
        }

        self.callbacks.removeAll()
    }

    // MARK: - Private

    static func getUrl(url: String, useDefault: Bool) -> String {
        let urlResult = url.hasSuffix("/") ? url : url.appending("/")

        if useDefault {
            return urlResult.appending("signalr")
        }

        return urlResult
    }

    // MARK - Sending Data

    override public func onSending() -> String {
        var data = [HubRegistrationData]()
        for key in self.hubs.keys {
            let registration = HubRegistrationData()
            registration.name = key
            data.append(registration)
        }

        return data.toJSONString()!
    }

    // MARK: - Received Data

    override public func didReceiveData(data: Any) {
        if let dict = data as? [String: Any] {
            if dict["I"] != nil, let result = HubResult(JSON: dict), let callback = self.callbacks[result.id!] {
                callback(result)
            } else if let invocation = HubInvocation(JSON: dict) {
                if let hubProxy = self.hubs[invocation.hub.lowercased()] {
                    if let state = invocation.state {
                        for key in state.keys {
                            hubProxy.state[key] = state[key]
                        }
                    }
                    hubProxy.invokeEvent(eventName: invocation.method, withArgs: invocation.args)
                }

                super.didReceiveData(data: data)
            }
        }
    }

    override public func willReconnect() {
        self.clearInvocationCallbacks(error: "Connection started reconnecting before invocation result was received.")
        super.willReconnect()
    }

    override func didClose() {
        self.clearInvocationCallbacks(error: "Connection was disconnected before invocation result was received.")
        super.didClose()
    }
}
