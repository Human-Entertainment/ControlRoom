//
//  SimulatorsController.swift
//  ControlRoom
//
//  Created by Dave DeLong on 2/12/20.
//  Copyright © 2020 Paul Hudson. All rights reserved.
//

import Combine
import Foundation
import SwiftUI

/// A centralized class that loads simulator data and handles filtering.
class SimulatorsController: ObservableObject {

    /// Tracks the state of fetching simulator data from simctl.
    enum LoadingStatus {
        /// Loading is in progress
        case loading

        /// Loading succeeded
        case success

        /// Loading failed
        case failed
    }

    /// The current loading state; defaults to .loading
    @Published var loadingStatus: LoadingStatus = .loading

    /// An array of all simulators that match the user's current filter.
    @Published var simulators = [Simulator]()

    /// An array of all simulators that were loaded from simctl.
    private var allSimulators = [Simulator]()

    /// A string that filters the list of available simulators.
    var filterText = "" {
        willSet { objectWillChange.send() }
        didSet { filterSimulators() }
    }

    /// The simulator the user is actively working with.
    var selectedSimulator: Simulator? {
        willSet { objectWillChange.send() }
    }

    private var cancellables = Set<AnyCancellable>()

    init() {
        loadSimulators()
    }

    /// Fetches all simulators from simctl.
    private func loadSimulators() {
        loadingStatus = .loading

        let devices = SimCtl.listDevices()
        let deviceTypes = SimCtl.listDeviceTypes()
        let runtimes = SimCtl.listRuntimes()

        devices.combineLatest(deviceTypes, runtimes)
            .receive(on: DispatchQueue.main)
            .sink(receiveCompletion: self.finishedLoadingSimulators,
                  receiveValue: self.handleLoadedInformation)
            .store(in: &cancellables)
    }

    private func handleLoadedInformation(_ deviceList: SimCtl.DeviceList, _ deviceTypes: SimCtl.DeviceTypeList, _ runtimes: SimCtl.RuntimeList) {
        var final = [Simulator]()

        let lookupDeviceType = Dictionary(grouping: deviceTypes.devicetypes, by: { $0.identifier }).compactMapValues({ $0.first })
        let lookupRuntime = Dictionary(grouping: runtimes.runtimes, by: { $0.identifier }).compactMapValues({ $0.first })
        for (runtimeIdentifier, devices) in deviceList.devices {
            let runtime: SimCtl.Runtime?
            if let known = lookupRuntime[runtimeIdentifier] {
                runtime = known
            } else if let parsed = SimCtl.Runtime(runtimeIdentifier: runtimeIdentifier) {
                runtime = parsed
            } else {
                runtime = nil
            }

            for device in devices {
                let model: TypeIdentifier
                if let deviceType = lookupDeviceType[device.deviceTypeIdentifier ?? ""], let modelType = deviceType.modelTypeIdentifier {
                    model = modelType
                } else if device.name.contains("iPad") {
                    model = .defaultiPad
                } else if device.name.contains("Watch") {
                    model = .defaultWatch
                } else if device.name.contains("TV") {
                    model = .defaultTV
                } else {
                    model = .defaultiPhone
                }

                let sim = Simulator(name: device.name, udid: device.udid, typeIdentifier: model, runtime: runtime)
                final.append(sim)
            }
        }

        objectWillChange.send()
        allSimulators = [.default] + final.sorted()
        filterSimulators()
    }

    private func finishedLoadingSimulators(_ completion: Subscribers.Completion<Command.CommandError>) {
        objectWillChange.send()
        switch completion {
        case .finished:
            loadingStatus = .success
        case .failure:
            loadingStatus = .failed
        }
    }

    /// Filters the list of simulators using `filterText`, and assigns the result to `simulators`.
    private func filterSimulators() {
        let trimmed = filterText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty == false {
            simulators = allSimulators.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
        } else {
            simulators = allSimulators
        }

        if let current = selectedSimulator {
            if simulators.firstIndex(of: current) == nil {
                // the current simulator is not in the list of filtered simulators
                // deselect it
                selectedSimulator = nil
            }
        }

        if selectedSimulator == nil {
            selectedSimulator = simulators.first
        }
    }

}
