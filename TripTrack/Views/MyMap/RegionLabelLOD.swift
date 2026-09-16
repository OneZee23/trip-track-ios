import CoreGraphics

/// Видна ли подпись региона или страны на этом масштабе.
///
/// Два независимых вопроса: bbox края на экране (в точках) — читается ли имя
/// вообще, — и `lod` слоя открытого (`RevealedLayer.LOD`, тот же ярус, что
/// решает толщину коридоров и наличие границ, `FogVeilRenderer.lod(for:)`) —
/// на КАКОМ масштабе вообще показывают регион, а на каком страну. Порог у
/// региона выше (140 pt — заголовок вроде «КРАСНОДАРСКИЙ КРАЙ» без обрезки),
/// у страны ниже (90 pt — короткое имя на мировом зуме).
///
/// Страна показывается ТОЛЬКО на `.far` — на любом более близком зуме её
/// подписывает уже регион.
///
/// А регион НЕ гаснет на `.far`, хотя изначально гас. Подпись региона
/// существует только у ПОСЕЩЁННОГО (`regionLabels(visitedRegionIds:)`), то
/// есть у того, который на дальнем уровне ещё и залит охрой
/// (`RegionPathIndex.fills(regions:)`); залитое пятно без имени — это
/// вопрос без ответа. Порога в 140 pt хватает, чтобы край, сжавшийся до
/// пикселя, всё равно молчал: его отсекает bbox, а не ярус.
enum RegionLabelLOD {
    static let regionMinSidePt: CGFloat = 140
    static let countryMinSidePt: CGFloat = 90

    static func level(bboxMinSidePt: CGFloat, lod: RevealedLayer.LOD, isCountry: Bool) -> Bool {
        _ = lod  // у региона ярус больше ничего не решает — см. комментарий выше
        if isCountry {
            return lod == .far && bboxMinSidePt >= countryMinSidePt
        }
        return bboxMinSidePt >= regionMinSidePt
    }
}
