import Foundation

enum ReferenceRegion: String, CaseIterable, Identifiable {
    case mainlandChina
    case hongKong
    case unitedStates
    case taiwan
    case singapore

    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .mainlandChina: "中国大陆"
        case .hongKong: "香港"
        case .unitedStates: "美国"
        case .taiwan: "台湾"
        case .singapore: "新加坡"
        }
    }
}

enum ChronicCondition: String, CaseIterable, Identifiable {
    case hypertension
    case type2Diabetes
    case dyslipidemia
    case hypothyroidism
    case gout

    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .hypertension: "高血压"
        case .type2Diabetes: "2型糖尿病"
        case .dyslipidemia: "血脂异常"
        case .hypothyroidism: "甲状腺功能减退"
        case .gout: "痛风与高尿酸血症"
        }
    }
}

struct MedicationReference: Identifiable {
    let id: String
    let genericName: String
    let condition: ChronicCondition
    let regions: Set<ReferenceRegion>
    let commonStrengths: [String]
    let exampleUse: LocalizedStringResource
    let mealGuidance: LocalizedStringResource
    let sourceTitle: String
    let sourceURL: URL
    let reviewedOn: Date
}

enum MedicationReferenceCatalog {
    static let entries: [MedicationReference] = [
        MedicationReference(
            id: "amlodipine", genericName: "Amlodipine / 氨氯地平",
            condition: .hypertension, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["2.5 mg", "5 mg", "10 mg"],
            exampleUse: "说明书常见成人起始用法示例：5 mg，每日一次；部分人群可能从2.5 mg开始。仅按处方确认。",
            mealGuidance: "通常可随餐或空腹服用。",
            sourceTitle: "DailyMed amlodipine label / Hong Kong HA Schedule 2",
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=amlodipine")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "losartan", genericName: "Losartan / 氯沙坦",
            condition: .hypertension, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["25 mg", "50 mg", "100 mg"],
            exampleUse: "说明书常见成人起始用法示例：50 mg，每日一次；剂量需结合血压、肾功能和医嘱确认。",
            mealGuidance: "通常可随餐或空腹服用。",
            sourceTitle: "US National Library of Medicine DailyMed",
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=ca012edc-923d-4ada-a261-db82b71b3c4f")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "indapamide", genericName: "Indapamide / 吲达帕胺",
            condition: .hypertension, regions: [.mainlandChina, .hongKong, .taiwan, .singapore],
            commonStrengths: ["1.5 mg ER", "2.5 mg"],
            exampleUse: "常见制剂包括1.5 mg缓释片和2.5 mg片；实际频次与剂量必须按处方确认。",
            mealGuidance: "通常安排在早晨，具体按药袋或处方。",
            sourceTitle: "Hong Kong Hospital Authority Schedule 2",
            sourceURL: URL(string: "https://www4.ha.org.hk/ppp/docs/default-source/gopc-ppp---useful-information/4b-booklet-of-schedule-%28eng%29_20241220.pdf")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "metformin-ir", genericName: "Metformin IR / 二甲双胍普通片",
            condition: .type2Diabetes, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["500 mg", "850 mg", "1000 mg"],
            exampleUse: "说明书常见成人起始用法示例：500 mg每日两次或850 mg每日一次；肾功能会影响是否适用。仅按处方确认。",
            mealGuidance: "普通片通常随餐服用，以减少胃肠道不适。",
            sourceTitle: "US National Library of Medicine DailyMed",
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=fb296500-55cb-45ce-be0c-59aa2e3d4624")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "metformin-er", genericName: "Metformin ER / 二甲双胍缓释片",
            condition: .type2Diabetes, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["500 mg", "750 mg", "1000 mg"],
            exampleUse: "说明书常见成人起始用法示例：500 mg，每日一次，随晚餐服用；缓释片通常应整片吞服。仅按处方确认。",
            mealGuidance: "通常随晚餐服用，不应自行压碎或咀嚼缓释片。",
            sourceTitle: "US National Library of Medicine DailyMed",
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=metformin%20extended%20release")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "gliclazide", genericName: "Gliclazide / 格列齐特",
            condition: .type2Diabetes, regions: [.mainlandChina, .hongKong, .taiwan, .singapore],
            commonStrengths: ["30 mg MR", "60 mg MR", "80 mg"],
            exampleUse: "普通片与缓释片用法不同，并可能引起低血糖；必须逐字核对处方上的剂型、剂量和频次。",
            mealGuidance: "通常与进餐相关，服药后应按医嘱进食。",
            sourceTitle: "Hong Kong Hospital Authority Drug Formulary",
            sourceURL: URL(string: "https://www.ha.org.hk/hadf/en/Others/Search-Result.html?cat=6")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "atorvastatin", genericName: "Atorvastatin / 阿托伐他汀",
            condition: .dyslipidemia, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["10 mg", "20 mg", "40 mg", "80 mg"],
            exampleUse: "说明书常见成人起始用法示例：10–20 mg，每日一次；治疗强度和相互作用需由医生确认。",
            mealGuidance: "每日固定时间服用，可随餐或空腹。",
            sourceTitle: "US National Library of Medicine DailyMed",
            sourceURL: URL(string: "https://www.dailymed.nlm.nih.gov/dailymed/drugInfo.cfm?setid=f7cc5704-2131-4bcb-9ff0-33a79a8167bd")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "levothyroxine", genericName: "Levothyroxine / 左甲状腺素",
            condition: .hypothyroidism, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["25 µg", "50 µg", "75 µg", "100 µg"],
            exampleUse: "剂量高度个体化，并需依据甲状腺功能复查调整；只录入处方上明确标注的剂量。",
            mealGuidance: "通常要求空腹并与部分药物或补充剂错开，具体按处方。",
            sourceTitle: "US National Library of Medicine DailyMed",
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=levothyroxine")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
        MedicationReference(
            id: "allopurinol", genericName: "Allopurinol / 别嘌醇",
            condition: .gout, regions: Set(ReferenceRegion.allCases),
            commonStrengths: ["100 mg", "300 mg"],
            exampleUse: "起始与维持剂量受肾功能、尿酸水平和严重皮肤反应风险影响；仅按处方录入。",
            mealGuidance: "通常建议餐后并配足量水服用，具体按处方。",
            sourceTitle: "US National Library of Medicine DailyMed",
            sourceURL: URL(string: "https://dailymed.nlm.nih.gov/dailymed/search.cfm?query=allopurinol")!,
            reviewedOn: Date(timeIntervalSince1970: 1_794_844_800)
        ),
    ]
}
