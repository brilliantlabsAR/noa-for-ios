//
//  LocationManager.swift
//  Noa
//
//  Created by Bart Trzynadlowski on 3/7/24.
//

import CoreLocation

class LocationManager: NSObject {
    private let _locationManager = CLLocationManager()
    private let _geocoder = CLGeocoder()

    private(set) var location: Location?

    override init() {
        super.init()
        _locationManager.delegate = self
        _locationManager.distanceFilter = 1   // 100 meters
        _locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        _locationManager.allowsBackgroundLocationUpdates = true
        _locationManager.requestWhenInUseAuthorization()
        startLocationUpdates()
    }

    private func startLocationUpdates() {
        DispatchQueue.global(qos: .default).async { [weak self] in
            guard let self = self else { return }
            guard CLLocationManager.locationServicesEnabled() else { return }
            DispatchQueue.main.async {
                //self._locationManager.startUpdatingLocation()
                self._locationManager.startMonitoringSignificantLocationChanges()

                //self.timer = Timer.scheduledTimer(timeInterval: 5, target: self, selector: #selector(self.updateLocation), userInfo: nil, repeats: true)
            }
            //self?._locationManager.startUpdatingLocation()
        }
    }

//    @objc private func updateLocation() {
//        guard let currentLocation = _locationManager.location else { return }
//        print(currentLocation)
//    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                startLocationUpdates()
            case .denied, .restricted, .notDetermined:
                break
            default:
                break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let location = locations.max(by: { $0.timestamp < $1.timestamp }) {
            // Geocoder requests are rate limited. Take care not to use this too often if the
            // frequency of location tracking is increased.
            _geocoder.reverseGeocodeLocation(location) { [weak self] (placemarks, error) in
                guard let self = self else { return }
                guard error == nil else {
                    print("[LocationManager] Geocoder error: \(error!.localizedDescription)")
                    return
                }
                if let placemark = placemarks?.first {
                    let streetAddress = [ placemark.subThoroughfare, placemark.thoroughfare ].compactMap({ $0 }).joined(separator: " ")
                    let fullAddress = [ streetAddress, placemark.locality, placemark.postalCode ].compactMap({ $0 }).joined(separator: ", ")
                    let address = fullAddress.count > 0 || placemark.name == nil ? fullAddress : placemark.name!
                    self.location = Location(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, address: address)
                    print("[LocationManager] Updated location: \(self.location!)")
                }
            }
        }
    }
}
