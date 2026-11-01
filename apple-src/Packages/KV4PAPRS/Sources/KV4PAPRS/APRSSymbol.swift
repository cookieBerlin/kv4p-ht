/// The beacon symbols the Android app offers (`APRSIconType`), all in the primary table `/`.
public enum APRSSymbol: String, CaseIterable, Codable, Sendable {
    case phone, person, house, bicycle, car, jeep, truck, motorcycle, van, rv, eighteenWheeler, glider
    case smallAircraft, helicopter, sailboat, motorboat

    public var code: Character { entry.code }

    public var name: String { entry.name }

    private var entry: (code: Character, name: String) {
        switch self {
        case .phone: ("$", "Phone")
        case .person: ("[", "Person")
        case .house: ("-", "House")
        case .bicycle: ("b", "Bicycle")
        case .car: (">", "Car")
        case .jeep: ("j", "Jeep")
        case .truck: ("k", "Truck")
        case .motorcycle: ("<", "Motorcycle")
        case .van: ("v", "Van")
        case .rv: ("R", "RV")
        case .eighteenWheeler: ("u", "18-wheeler")
        case .glider: ("g", "Glider")
        case .smallAircraft: ("'", "Small aircraft")
        case .helicopter: ("X", "Helicopter")
        case .sailboat: ("Y", "Sailboat")
        case .motorboat: ("s", "Motorboat")
        }
    }
}
