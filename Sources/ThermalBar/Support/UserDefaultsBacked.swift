import Foundation

@propertyWrapper
struct UserDefaultsBacked<Value> {
    let key: String
    let defaultValue: Value
    var store: UserDefaults = .standard

    var wrappedValue: Value {
        get {
            store.object(forKey: key) as? Value ?? defaultValue
        }
        set {
            store.set(newValue, forKey: key)
        }
    }
}
