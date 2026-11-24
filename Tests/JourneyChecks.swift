import Foundation
@main struct JourneyChecks {
    static func main() throws {
        let p = JourneyPoint(latitude:0,longitude:0), q = JourneyPoint(latitude:0.01,longitude:0)
        let start = Date(timeIntervalSince1970:1000)
        let a = JourneyLeg(title:"Meal",mode:"stay",start:start,end:start.addingTimeInterval(100),timeZone:"Etc/UTC",notes:nil,points:[p])
        let b = JourneyLeg(title:"Walk",mode:"walk",start:a.end,end:a.end.addingTimeInterval(200),timeZone:"Etc/UTC",notes:nil,points:[p,q])
        let c = JourneyLeg(title:"Rest",mode:"stay",start:b.end,end:b.end.addingTimeInterval(300),timeZone:"Etc/UTC",notes:nil,points:[q])
        let plan = JourneyPlan(version:1,title:"Test",legs:[a,b,c])
        let schedule = try JourneySchedule(plan)
        precondition(schedule.frame(at:start.addingTimeInterval(-1)).label == "Waiting for start")
        precondition(schedule.frame(at:start).label == "Meal")
        precondition(schedule.frame(at:b.start).label == "Walk")
        precondition(abs(schedule.frame(at:b.start.addingTimeInterval(100)).point.latitude-0.005)<0.000001)
        precondition(schedule.frame(at:c.start).label == "Rest")
        precondition(schedule.frame(at:c.end).finished)
        let invalid = JourneyPlan(version:1,title:"Invalid",legs:[a,c])
        do {try invalid.validate(); fatalError("Gap accepted")} catch {}
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoded = try JourneyPlan.decode(encoder.encode(plan)); precondition(decoded.legs.count == 3)
        print("Journey schedule checks passed")
    }
}
