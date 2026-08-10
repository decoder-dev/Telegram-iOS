import Foundation

private let secureIdTD1Length = 30
private let secureIdTD23Length = 44
private let secureIdEmpty = "<"

struct SecureIdMRZ {
    var documentType: String?
    var documentSubtype: String?
    var issuingCountry: String?
    var firstName: String
    var middleName: String?
    var lastName: String
    var nativeFirstName: String?
    var nativeMiddleName: String?
    var nativeLastName: String?
    var documentNumber: String?
    var nationality: String?
    var birthDate: Date?
    var gender: String?
    var expiryDate: Date?
    var optional1: String?
    var optional2: String?
    var mrz: String?
    
    static func parseBarcodePayload(_ data: String) -> SecureIdMRZ? {
        if data.isEmpty {
            return nil
        }
        
        if data.contains("ANSI ") {
            var fields: [String: String] = [:]
            data.enumerateLines { line, _ in
                if line.count >= 4 && line.hasPrefix("D") {
                    fields[String(line.prefix(3))] = String(line.dropFirst(3))
                }
            }
            if fields.isEmpty {
                return nil
            }
            
            var result = SecureIdMRZ(documentType: "DL", issuingCountry: fields["DCG"], firstName: fields["DAC"] ?? fields["DCT"] ?? "", middleName: fields["DAD"], lastName: fields["DCS"] ?? fields["DAB"] ?? "", documentNumber: fields["DCF"])
            switch fields["DBC"] {
            case "1":
                result.gender = "M"
            case "2":
                result.gender = "F"
            default:
                break
            }
            
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "MMddyyyy"
            if let value = fields["DBA"], !value.isEmpty {
                result.expiryDate = formatter.date(from: value)
            }
            if let value = fields["DBB"], !value.isEmpty {
                result.birthDate = formatter.date(from: value)
            }
            return result
        }
        
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        if data.rangeOfCharacter(from: allowed.inverted) != nil {
            return nil
        }
        guard let decodedData = Data(base64Encoded: data) else {
            return nil
        }
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.windowsCyrillic.rawValue)))
        guard let decodedString = String(data: decodedData, encoding: encoding), !decodedString.isEmpty else {
            return nil
        }
        let components = decodedString.components(separatedBy: "|")
        if components.count < 7 {
            return nil
        }
        
        var result = SecureIdMRZ(
            documentType: "DL",
            issuingCountry: "RUS",
            firstName: transliterateRussianName(components[4]),
            middleName: transliterateRussianName(components[5]),
            lastName: transliterateRussianName(components[3]),
            nativeFirstName: components[4],
            nativeMiddleName: components[5],
            nativeLastName: components[3],
            documentNumber: components[0],
            nationality: "RUS"
        )
        
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        if !components[6].isEmpty {
            result.birthDate = formatter.date(from: components[6])
        }
        if !components[2].isEmpty {
            result.expiryDate = formatter.date(from: components[2])
        }
        return result
    }
    
    static func parseLines(_ lines: [String]) -> SecureIdMRZ? {
        if lines.count == 2 {
            guard lines[0].count == secureIdTD23Length, lines[1].count == secureIdTD23Length else {
                return nil
            }
            
            var result = SecureIdMRZ(
                documentType: lines[0].substring(from: 0, length: 1),
                documentSubtype: clean(lines[0].substring(from: 1, length: 1)),
                issuingCountry: clean(lines[0].substring(from: 2, length: 3)),
                firstName: "",
                lastName: ""
            )
            
            let fullName = lines[0].substring(from: 5, length: 39).trimmingCharacters(in: CharacterSet(charactersIn: secureIdEmpty))
            let names = fullName.components(separatedBy: "<<")
            result.lastName = nameString(names.first ?? "")
            result.firstName = nameString(names.last ?? "")
            
            let documentNumber = ensureNumber(lines[1].substring(from: 0, length: 9))
            let documentNumberCheck = Int(ensureNumber(lines[1].substring(from: 9, length: 1))) ?? 0
            if isDataValid(documentNumber, check: documentNumberCheck) {
                result.documentNumber = documentNumber
            }
            
            result.nationality = lines[1].substring(from: 10, length: 3)
            
            let birthDate = ensureNumber(lines[1].substring(from: 13, length: 6))
            let birthDateCheck = Int(ensureNumber(lines[1].substring(from: 19, length: 1))) ?? 0
            if isDataValid(birthDate, check: birthDateCheck) {
                result.birthDate = dateFromString(birthDate)
            }
            
            let gender = lines[1].substring(from: 20, length: 1)
            result.gender = gender == secureIdEmpty ? nil : gender
            
            let expiryDate = ensureNumber(lines[1].substring(from: 21, length: 6))
            let expiryDateCheck = Int(ensureNumber(lines[1].substring(from: 27, length: 1))) ?? 0
            if isDataValid(expiryDate, check: expiryDateCheck) {
                result.expiryDate = dateFromString(expiryDate)
            }
            
            let optional1 = lines[1].substring(from: 28, length: 14)
            let optional1CheckString = ensureNumber(lines[1].substring(from: 42, length: 1))
            let optional1Check = optional1CheckString == secureIdEmpty ? 0 : (Int(optional1CheckString) ?? 0)
            if isDataValid(optional1, check: optional1Check) {
                result.optional1 = clean(optional1)
            }
            
            let data = "\(documentNumber)\(documentNumberCheck)\(birthDate)\(birthDateCheck)\(expiryDate)\(expiryDateCheck)\(optional1)\(optional1CheckString)"
            let dataCheck = Int(ensureNumber(lines[1].substring(from: 43, length: 1))) ?? 0
            if isDataValid(data, check: dataCheck) {
                if result.documentType == "P", result.documentSubtype == "N", result.issuingCountry == "RUS" {
                    let nativeLastName = transliterateRussianMRZString(result.lastName)
                    result.nativeLastName = nativeLastName
                    result.lastName = transliterateRussianName(nativeLastName)
                    
                    let nativeFirstName = transliterateRussianMRZString(result.firstName)
                    result.nativeFirstName = nativeFirstName
                    result.firstName = transliterateRussianName(nativeFirstName)
                    
                    if let documentNumber = result.documentNumber {
                        result.documentNumber = documentNumber.substring(from: 0, length: 3) + optional1.substring(from: 0, length: 1) + documentNumber.substring(from: 3, length: documentNumber.count - 3)
                    }
                }
                result.mrz = lines.joined(separator: "\n")
                return result
            }
        } else if lines.count == 3 {
            guard lines[0].count == secureIdTD1Length, lines[1].count == secureIdTD1Length, lines[2].count == secureIdTD1Length else {
                return nil
            }
            
            var result = SecureIdMRZ(
                documentType: lines[0].substring(from: 0, length: 1),
                documentSubtype: clean(lines[0].substring(from: 1, length: 1)),
                issuingCountry: clean(lines[0].substring(from: 2, length: 3)),
                firstName: "",
                lastName: ""
            )
            
            let documentNumber = ensureNumber(lines[0].substring(from: 5, length: 9))
            let documentNumberCheck = Int(ensureNumber(lines[0].substring(from: 14, length: 1))) ?? 0
            if isDataValid(documentNumber, check: documentNumberCheck) {
                result.documentNumber = documentNumber
            }
            let optional1 = lines[0].substring(from: 15, length: 15)
            result.optional1 = clean(optional1)
            
            let birthDate = ensureNumber(lines[1].substring(from: 0, length: 6))
            let birthDateCheck = Int(lines[1].substring(from: 6, length: 1)) ?? 0
            if isDataValid(birthDate, check: birthDateCheck) {
                result.birthDate = dateFromString(birthDate)
            }
            
            let gender = lines[1].substring(from: 7, length: 1)
            result.gender = gender == secureIdEmpty ? nil : gender
            
            let expiryDate = ensureNumber(lines[1].substring(from: 8, length: 6))
            let expiryDateCheck = Int(ensureNumber(lines[1].substring(from: 14, length: 1))) ?? 0
            if isDataValid(expiryDate, check: expiryDateCheck) {
                result.expiryDate = dateFromString(expiryDate)
            }
            
            result.nationality = lines[1].substring(from: 15, length: 3)
            result.optional2 = lines[1].substring(from: 18, length: 11)
            
            let fullName = ensureAlpha(lines[2]).trimmingCharacters(in: CharacterSet(charactersIn: secureIdEmpty))
            let names = fullName.components(separatedBy: "<<")
            result.lastName = nameString(names.first ?? "")
            result.firstName = nameString(names.last ?? "")
            result.mrz = lines.joined(separator: "\n")
            return result
        }
        
        return nil
    }
}

private extension SecureIdMRZ {
    init(documentType: String? = nil, documentSubtype: String? = nil, issuingCountry: String? = nil, firstName: String, middleName: String? = nil, lastName: String, nativeFirstName: String? = nil, nativeMiddleName: String? = nil, nativeLastName: String? = nil, documentNumber: String? = nil, nationality: String? = nil, birthDate: Date? = nil, gender: String? = nil, expiryDate: Date? = nil, optional1: String? = nil, optional2: String? = nil, mrz: String? = nil) {
        self.documentType = documentType
        self.documentSubtype = documentSubtype
        self.issuingCountry = issuingCountry
        self.firstName = firstName
        self.middleName = middleName
        self.lastName = lastName
        self.nativeFirstName = nativeFirstName
        self.nativeMiddleName = nativeMiddleName
        self.nativeLastName = nativeLastName
        self.documentNumber = documentNumber
        self.nationality = nationality
        self.birthDate = birthDate
        self.gender = gender
        self.expiryDate = expiryDate
        self.optional1 = optional1
        self.optional2 = optional2
        self.mrz = mrz
    }
}

private func dateFromString(_ string: String) -> Date? {
    struct Holder {
        static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "YYMMdd"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            return formatter
        }()
    }
    return Holder.formatter.date(from: string)
}

private func clean(_ string: String) -> String {
    return string.replacingOccurrences(of: secureIdEmpty, with: "")
}

private func nameString(_ string: String) -> String {
    return string.replacingOccurrences(of: secureIdEmpty, with: " ")
}

private func ensureNumber(_ string: String) -> String {
    return string
        .replacingOccurrences(of: "O", with: "0")
        .replacingOccurrences(of: "U", with: "0")
        .replacingOccurrences(of: "Q", with: "0")
        .replacingOccurrences(of: "J", with: "0")
}

private func ensureAlpha(_ string: String) -> String {
    let valid = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ<")
    return string.replacingOccurrences(of: "0", with: "O").map { character -> String in
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1, valid.contains(scalar) else {
            return secureIdEmpty
        }
        return String(character)
    }.joined()
}

private func transliterateRussianMRZString(_ string: String) -> String {
    let map: [Character: String] = ["A": "А", "B": "Б", "V": "В", "G": "Г", "D": "Д", "E": "Е", "2": "Ё", "J": "Ж", "Z": "З", "I": "И", "Q": "Й", "K": "К", "L": "Л", "M": "М", "N": "Н", "O": "О", "P": "П", "R": "Р", "S": "С", "T": "Т", "U": "У", "F": "Ф", "H": "Х", "C": "Ц", "3": "Ч", "4": "Ш", "W": "Щ", "X": "Ъ", "Y": "Ы", "9": "Ь", "6": "Э", "7": "Ю", "8": "Я", " ": " "]
    return string.compactMap { map[$0] }.joined()
}

private func transliterateRussianName(_ string: String) -> String {
    let map: [Character: String] = ["А": "A", "Б": "B", "В": "V", "Г": "G", "Д": "D", "Е": "E", "Ё": "E", "Ж": "ZH", "З": "Z", "И": "I", "Й": "I", "К": "K", "Л": "L", "М": "M", "Н": "N", "О": "O", "П": "P", "Р": "R", "С": "S", "Т": "T", "У": "U", "Ф": "F", "Х": "KH", "Ц": "TS", "Ч": "CH", "Ш": "SH", "Щ": "SHCH", "Ъ": "IE", "Ы": "Y", "Ь": "", "Э": "E", "Ю": "IU", "Я": "IA", " ": " "]
    return string.compactMap { map[$0] }.joined()
}

private func isDataValid(_ data: String, check: Int) -> Bool {
    var sum = 0
    let weights = [7, 3, 1]
    for (index, scalar) in data.unicodeScalars.enumerated() {
        let value: Int
        if scalar.value >= 48 && scalar.value <= 57 {
            value = Int(scalar.value - 48)
        } else if scalar.value >= 65 && scalar.value <= 90 {
            value = Int(10 + scalar.value - 65)
        } else if scalar == "<" {
            value = 0
        } else {
            return false
        }
        sum += value * weights[index % 3]
    }
    return sum % 10 == check
}

private extension String {
    func substring(from offset: Int, length: Int) -> String {
        if offset < 0 || length <= 0 || offset >= self.count {
            return ""
        }
        let lower = self.index(self.startIndex, offsetBy: offset)
        let upper = self.index(lower, offsetBy: min(length, self.distance(from: lower, to: self.endIndex)))
        return String(self[lower ..< upper])
    }
}
