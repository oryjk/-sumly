import Foundation
import Testing
@testable import Sumly
@Test func logarithmicChartUsesEqualSpacingForEqualPriceRatios() {
    let scale = ChartPriceScale.logarithmic
    #expect(abs((scale.value(100)! - scale.value(10)!) - (scale.value(1000)! - scale.value(100)!)) < 0.000001)
    #expect(ChartPriceScale.linear.value(100) == 100)
    #expect(scale.value(0) == nil)
    #expect(scale.value(-1) == nil)
    #expect(scale.value(.infinity) == nil)
}
@Test func logarithmicChartDomainsAreFiniteForEmptyAndConstantData() {
    for values in [[], [100.0], [0, -1, .nan], [1, 10000]] {
        let domain = ChartPriceScale.logarithmic.domain(values)
        #expect(domain.lowerBound.isFinite && domain.upperBound.isFinite && domain.lowerBound < domain.upperBound)
    }
}
