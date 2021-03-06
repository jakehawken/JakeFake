//  Faker.swift
//  Poseur
//  Created by Jacob Hawken on 1/17/21.

import Foundation

public extension PoseurFunction {
    static func faker() -> Faker<Self> {
        return Faker<Self>()
    }
}

public class Faker<Function: PoseurFunction> {
    
    private var methodCalls = [RecordedCall]()
    private var argsAgnosticStubs = [Function: Stub]()
    private var argsSpecificStubs = [Function: [Stub]]()
    
    private struct RecordedCall {
        let function: Function
        let arguments: [Any?]
    }
    
    private struct Stub {
        let function: Function
        let argsCheck: Fake.ArgsCheck?
        let execution: Fake.FunctionCall
        
        func argumentsPassCheck(_ args: [Any?]) -> Bool {
            argsCheck?(args) ?? true
        }
    }
    
}

// MARK: - Resetting

extension Faker {
    
    func reset() {
        methodCalls.removeAll()
        argsAgnosticStubs.removeAll()
        argsSpecificStubs.removeAll()
    }
    
    func resetFunction(_ function: Function) {
        removeMethodCalls(for: function)
        removeAllStubs(for: function)
    }
    
    func removeMethodCalls(for function: Function) {
        methodCalls = methodCalls.filter { $0.function != function }
    }
    
    func removeUniversalStub(for function: Function) {
        argsAgnosticStubs.removeValue(forKey: function)
    }
    
    func removeAllStubs(for function: Function) {
        removeUniversalStub(for: function)
        argsSpecificStubs.removeValue(forKey: function)
    }
    
}

// MARK: - Spying

public extension Faker {
    
    internal func recordCall(_ method: Function, arguments: [Any?]) {
        let call = RecordedCall(function: method, arguments: arguments)
        methodCalls.append(call)
    }
    
    func callCountFor(function: Function) -> Int {
        return methodCalls.filter { (call) -> Bool in
            call.function == function
        }.count
    }
    
    func callCountFor(function: Function, where argsMatch: Fake.ArgsCheck) -> Int {
        return methodCalls.filter { (call) -> Bool in
            call.function == function && argsMatch(call.arguments)
        }.count
    }
    
    func callCountForFunction(_ function: Function, withArguments args: [Any?]) -> Int {
        let argsCheck = argumentWrapperCheck(fromArgs: args)
        return callCountFor(function: function, where: argsCheck)
    }
    
    func receivedCall(to function: Function) -> Bool {
        return callCountFor(function: function) > 0
    }
    
    func receivedCall(to function: Function, where argsMatch: Fake.ArgsCheck) -> Bool {
        return callCountFor(function: function, where: argsMatch) > 0
    }
    
    func receivedCall(to function: Function, withArguments args: [Any?]) -> Bool {
        return callCountForFunction(function, withArguments: args) > 0
    }
}

// MARK: - Stubbing

public extension Faker {
    
    func stub(function: Function) -> Stubbable {
        return StubMaker { [weak self] (stubbedAction) in
            let stub = Stub(function: function,
                            argsCheck: nil,
                            execution: stubbedAction)
            self?.argsAgnosticStubs[function] = stub
        }
    }
    
    func stub(function: Function, where argsCheck: @escaping Fake.ArgsCheck) -> Stubbable {
        return StubMaker { [weak self] (stubbedAction) in
            let stub = Stub(function: function,
                            argsCheck: argsCheck,
                            execution: stubbedAction)
            if self?.argsSpecificStubs[function] != nil {
                self?.argsSpecificStubs[function]?.append(stub)
            }
            else {
                self?.argsSpecificStubs[function] = [stub]
            }
        }
    }
    
    func stub(function: Function, withArgs args: [Any?]) -> Stubbable {
        let argsCheck = argumentWrapperCheck(fromArgs: args)
        return StubMaker { [weak self] (stubbedAction) in
            let stub = Stub(function: function,
                            argsCheck: argsCheck,
                            execution: stubbedAction)
            if self?.argsSpecificStubs[function] != nil {
                self?.argsSpecificStubs[function]?.append(stub)
            }
            else {
                self?.argsSpecificStubs[function] = [stub]
            }
        }
    }
    
    func stubbedValue(forFunction function: Function, arguments: [Any?]) -> Any? {
        if let godStub = argsAgnosticStubs[function] {
            return godStub.execution(arguments)
        }
        let specificStubs = argsSpecificStubs[function]
        let firstMatch = specificStubs?.first(where: { $0.argumentsPassCheck(arguments) })
        guard let specificStub = firstMatch else {
            fatalError("No stubs found for \(function).")
        }
        return specificStub.execution(arguments)
    }
    
}

// MARK: - Private / Helpers

private extension Faker {
    
    func argumentWrapperCheck(fromArgs args: [Any?]) -> Fake.ArgsCheck {
        let wrappers = args.map { ArgumentWrapper($0) }
        return { (arguments) -> Bool in
            guard arguments.count == wrappers.count else {
                fatalError("Wrong number of stubbed arguments. Expected \(wrappers.count). Received \(arguments.count).")
            }
            let zipped = zip(arguments, wrappers)
            return zipped.allSatisfy { (argPair) -> Bool in
                argPair.1.matchesArgument(argPair.0)
            }
        }
    }
    
}

private struct StubMaker: Stubbable {
    
    private(set) var actionAdded = false
    private let callback: (@escaping Fake.FunctionCall) -> Void
    
    fileprivate init(_ callback: @escaping (@escaping Fake.FunctionCall) -> Void) {
        self.callback = callback
    }
    
    func andDo(_ action: @escaping Fake.FunctionCall) {
        if actionAdded {
            fatalError("A callback has already beed added for this stub.")
        }
        callback(action)
    }
    
    func andReturn(_ value: Any?) {
        andDo { (_) -> Any? in
            return value
        }
    }
    
}
