import AppKit

public class SVGPath {
    public let bezierPath: NSBezierPath
    
    public init(svgPathString: String, viewBox: CGRect, targetRect: CGRect) {
        self.bezierPath = NSBezierPath()
        
        let scaleX = targetRect.width / viewBox.width
        let scaleY = targetRect.height / viewBox.height
        let offsetX = targetRect.minX
        let offsetY = targetRect.minY
        
        func transformX(_ x: CGFloat) -> CGFloat {
            return offsetX + x * scaleX
        }
        
        func transformY(_ y: CGFloat) -> CGFloat {
            // Flip Y coordinate for macOS Coordinate System (Y-up inside NSImage)
            return offsetY + targetRect.height - y * scaleY
        }
        
        // Manual character parsing to tokenize the SVG path string robustly
        var tokens: [String] = []
        let commands = CharacterSet(charactersIn: "MmLlaAcCzsSzHhVvqQtTeEdD")
        let separators = CharacterSet(charactersIn: " ,\t\r\n")
        
        var index = svgPathString.startIndex
        while index < svgPathString.endIndex {
            let char = svgPathString[index]
            if commands.contains(char.unicodeScalars.first!) {
                tokens.append(String(char))
                index = svgPathString.index(after: index)
            } else if separators.contains(char.unicodeScalars.first!) {
                index = svgPathString.index(after: index)
            } else {
                let start = index
                while index < svgPathString.endIndex {
                    let nextChar = svgPathString[index]
                    if commands.contains(nextChar.unicodeScalars.first!) || separators.contains(nextChar.unicodeScalars.first!) {
                        break
                    }
                    if nextChar == "-" && index != start {
                        break
                    }
                    index = svgPathString.index(after: index)
                }
                tokens.append(String(svgPathString[start..<index]))
            }
        }
        
        var i = 0
        var currentPoint = CGPoint.zero
        var pathStartPoint = CGPoint.zero
        
        while i < tokens.count {
            let token = tokens[i]
            guard token.count == 1, let cmd = token.first else {
                i += 1
                continue
            }
            i += 1
            
            switch cmd {
            case "M", "m":
                guard i + 1 < tokens.count,
                      let x = Double(tokens[i]),
                      let y = Double(tokens[i+1]) else { break }
                i += 2
                
                let targetX = (cmd == "m") ? (currentPoint.x + CGFloat(x)) : CGFloat(x)
                let targetY = (cmd == "m") ? (currentPoint.y + CGFloat(y)) : CGFloat(y)
                
                let nsPoint = CGPoint(x: transformX(targetX), y: transformY(targetY))
                bezierPath.move(to: nsPoint)
                currentPoint = CGPoint(x: targetX, y: targetY)
                pathStartPoint = currentPoint
                
            case "L", "l":
                guard i + 1 < tokens.count,
                      let x = Double(tokens[i]),
                      let y = Double(tokens[i+1]) else { break }
                i += 2
                
                let targetX = (cmd == "l") ? (currentPoint.x + CGFloat(x)) : CGFloat(x)
                let targetY = (cmd == "l") ? (currentPoint.y + CGFloat(y)) : CGFloat(y)
                
                let nsPoint = CGPoint(x: transformX(targetX), y: transformY(targetY))
                bezierPath.line(to: nsPoint)
                currentPoint = CGPoint(x: targetX, y: targetY)
                
            case "C", "c":
                guard i + 5 < tokens.count,
                      let x1 = Double(tokens[i]),
                      let y1 = Double(tokens[i+1]),
                      let x2 = Double(tokens[i+2]),
                      let y2 = Double(tokens[i+3]),
                      let x = Double(tokens[i+4]),
                      let y = Double(tokens[i+5]) else { break }
                i += 6
                
                let cx1 = (cmd == "c") ? (currentPoint.x + CGFloat(x1)) : CGFloat(x1)
                let cy1 = (cmd == "c") ? (currentPoint.y + CGFloat(y1)) : CGFloat(y1)
                let cx2 = (cmd == "c") ? (currentPoint.x + CGFloat(x2)) : CGFloat(x2)
                let cy2 = (cmd == "c") ? (currentPoint.y + CGFloat(y2)) : CGFloat(y2)
                let tx = (cmd == "c") ? (currentPoint.x + CGFloat(x)) : CGFloat(x)
                let ty = (cmd == "c") ? (currentPoint.y + CGFloat(y)) : CGFloat(y)
                
                bezierPath.curve(
                    to: CGPoint(x: transformX(tx), y: transformY(ty)),
                    controlPoint1: CGPoint(x: transformX(cx1), y: transformY(cy1)),
                    controlPoint2: CGPoint(x: transformX(cx2), y: transformY(cy2))
                )
                currentPoint = CGPoint(x: tx, y: ty)
                
            case "A", "a":
                guard i + 6 < tokens.count,
                      let rx = Double(tokens[i]),
                      let _ = Double(tokens[i+1]), // ry (unused in circular approximation)
                      let _ = Double(tokens[i+2]), // xAxisRotation (unused)
                      let _ = Double(tokens[i+3]), // largeArcFlag (unused)
                      let sweepFlag = Double(tokens[i+4]),
                      let x = Double(tokens[i+5]),
                      let y = Double(tokens[i+6]) else { break }
                i += 7
                
                let tx = (cmd == "a") ? (currentPoint.x + CGFloat(x)) : CGFloat(x)
                let ty = (cmd == "a") ? (currentPoint.y + CGFloat(y)) : CGFloat(y)
                
                let dx = tx - currentPoint.x
                let dy = ty - currentPoint.y
                let d = sqrt(dx*dx + dy*dy)
                let r = CGFloat(rx)
                
                // Height of circular segment: h = r - sqrt(max(0, r^2 - (d/2)^2))
                let h: CGFloat
                if r > d / 2 {
                    h = r - sqrt(r*r - (d/2)*(d/2))
                } else {
                    h = d / 2
                }
                
                // Perpendicular vector along Y for horizontal offset
                let px = dy / (d == 0 ? 1 : d)
                let py = -dx / (d == 0 ? 1 : d)
                
                let factor: CGFloat = (sweepFlag == 1) ? 1 : -1
                let cpOffsetX = px * h * factor * (4.0 / 3.0)
                let cpOffsetY = py * h * factor * (4.0 / 3.0)
                
                let cp1 = CGPoint(
                    x: transformX(currentPoint.x + dx/3 + cpOffsetX),
                    y: transformY(currentPoint.y + dy/3 + cpOffsetY)
                )
                let cp2 = CGPoint(
                    x: transformX(tx - dx/3 + cpOffsetX),
                    y: transformY(ty - dy/3 + cpOffsetY)
                )
                
                bezierPath.curve(
                    to: CGPoint(x: transformX(tx), y: transformY(ty)),
                    controlPoint1: cp1,
                    controlPoint2: cp2
                )
                currentPoint = CGPoint(x: tx, y: ty)
                
            case "Z", "z":
                bezierPath.close()
                currentPoint = pathStartPoint
                
            default:
                break
            }
        }
    }
}
