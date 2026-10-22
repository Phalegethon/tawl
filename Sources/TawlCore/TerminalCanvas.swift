/// Semantic colours kept separate from text so process names cannot inject ANSI.
public enum TerminalInk: Equatable, Sendable {
    case primary, secondary, muted, border, cpu, gpu, memory, disk, network, good, warning, danger

    fileprivate var colour: Int {
        switch self {
        case .primary: return 255
        case .secondary: return 252
        case .muted: return 245
        case .border: return 240
        case .cpu: return 81
        case .gpu: return 141
        case .memory, .warning: return 221
        case .disk: return 75
        case .network, .good: return 114
        case .danger: return 203
        }
    }
}

public enum TerminalFill: Equatable, Sendable {
    case none, panel, selected

    fileprivate var ansi: String {
        switch self {
        case .none: return "49"
        case .panel: return "48;5;235"
        case .selected: return "48;5;23"
        }
    }
}

/// A fixed rectangle measured in terminal cells, not Unicode scalar count.
public struct TerminalCanvas {
    private struct Cell {
        var text = " "
        // A zero span belongs to the wide glyph immediately to its left.
        var span = 1
        var ink: TerminalInk = .primary
        var fill: TerminalFill = .none
    }

    public let width: Int
    public let height: Int
    private var rows: [[Cell]]

    public init(width: Int, height: Int) {
        self.width = max(0, width)
        self.height = max(0, height)
        rows = Array(repeating: Array(repeating: Cell(), count: self.width), count: self.height)
    }

    /// Clips whole glyphs at either edge. The default fill preserves an existing row fill.
    public mutating func write(_ text: String, x: Int, y: Int, ink: TerminalInk = .primary, fill: TerminalFill = .none) {
        guard y >= 0, y < height, width > 0 else { return }
        var column = x
        for character in TerminalText.sanitize(text) {
            let glyph = String(character)
            let span = TerminalText.width(glyph)
            guard span > 0 else { continue }
            if column >= width { break }
            if column < 0 { column += span; continue }
            if span > width - column { break }

            let background = fill == .none ? rows[y][column].fill : fill
            for covered in column..<(column + span) { clearGlyph(at: covered, y: y) }
            rows[y][column] = Cell(text: glyph, span: span, ink: ink, fill: background)
            if span > 1 {
                for covered in (column + 1)..<(column + span) {
                    rows[y][covered] = Cell(text: "", span: 0, ink: ink, fill: background)
                }
            }
            column += span
        }
    }

    /// Paints the half-open cell range while retaining its text and foreground.
    public mutating func fillRow(y: Int, from: Int = 0, to: Int? = nil, fill: TerminalFill) {
        guard y >= 0, y < height else { return }
        let start = max(0, min(width, from))
        let end = max(start, min(width, to ?? width))
        for column in start..<end {
            var origin = column
            while origin > 0 && rows[y][origin].span == 0 { origin -= 1 }
            for covered in origin..<min(width, origin + rows[y][origin].span) {
                rows[y][covered].fill = fill
            }
        }
    }

    public mutating func box(x: Int, y: Int, width: Int, height: Int, title: String = "", ink: TerminalInk = .border) {
        guard width > 0, height > 0 else { return }
        if height == 1 {
            write(String(repeating: "─", count: width), x: x, y: y, ink: ink)
            return
        }
        if width == 1 {
            for row in y..<(y + height) { write("│", x: x, y: row, ink: ink) }
            return
        }
        let rule = String(repeating: "─", count: width - 2)
        write("╭" + rule + "╮", x: x, y: y, ink: ink)
        write("╰" + rule + "╯", x: x, y: y + height - 1, ink: ink)
        if height > 2 {
            for row in (y + 1)..<(y + height - 1) {
                write("│", x: x, y: row, ink: ink)
                write("│", x: x + width - 1, y: row, ink: ink)
            }
        }
        if !title.isEmpty && width > 4 {
            let label = TerminalText.clipped(title, to: width - 4)
            write(" " + label + " ", x: x + 1, y: y, ink: ink)
        }
    }

    public var lines: [String] {
        rows.map { row in row.map(\.text).joined() }
    }

    /// Copies a clipped viewport without converting cells back through ANSI text.
    public mutating func copy(_ source:TerminalCanvas,fromRow:Int=0,toX:Int,toY:Int,rowCount:Int) {
        guard rowCount>0 else {return}
        for row in 0..<rowCount {
            let sy=fromRow+row,dy=toY+row
            guard sy>=0,sy<source.height,dy>=0,dy<height else {continue}
            for column in 0..<source.width {
                let dx=toX+column
                guard dx>=0,dx<width else {continue}
                let cell=source.rows[sy][column]
                if cell.span==0 {continue}
                guard dx+cell.span<=width else {continue}
                write(cell.text,x:dx,y:dy,ink:cell.ink,fill:cell.fill)
            }
        }
    }

    /// Only internally generated SGR sequences are emitted. Every row resets its style.
    public func ansiLines(colors: Bool = true) -> [String] {
        guard colors else { return lines }
        return rows.map { row in
            var result = ""
            var previousInk: TerminalInk?
            var previousFill: TerminalFill?
            for cell in row where cell.span > 0 {
                if previousInk != cell.ink || previousFill != cell.fill {
                    result += "\u{1b}[38;5;\(cell.ink.colour);\(cell.fill.ansi)m"
                    previousInk = cell.ink
                    previousFill = cell.fill
                }
                result += cell.text
            }
            return result + "\u{1b}[0m"
        }
    }

    private mutating func clearGlyph(at column: Int, y: Int) {
        var origin = column
        while origin > 0 && rows[y][origin].span == 0 { origin -= 1 }
        let end = min(width, origin + rows[y][origin].span)
        for covered in origin..<end {
            rows[y][covered].text = " "
            rows[y][covered].span = 1
        }
    }
}

/// Borderless plots, oldest sample on the left. Missing samples are never zeroes.
public enum TerminalPlot {
    private enum Sample {
        case padding, missing, value(Double)
    }
    private static let vertical = Array(" ▁▂▃▄▅▆▇█")
    private static let horizontal = Array("░▏▎▍▌▋▊▉█")

    public static func sparkline(_ values: [Double?], width: Int, ceiling: Double? = nil) -> String {
        guard width > 0 else { return "" }
        let samples = samples(values, width: width)
        let scale = scale(values, ceiling: ceiling)
        return String(samples.map { sample in
            switch sample {
            case .padding: return " "
            case .missing: return "·"
            case .value(let value):
                return vertical[max(1, Int((min(1, value / scale) * 8).rounded(.up)))]
            }
        })
    }

    public static func bars(_ values: [Double?], width: Int, height: Int, ceiling: Double? = nil) -> [String] {
        guard height > 0 else { return [] }
        guard width > 0 else { return Array(repeating: "", count: height) }
        let samples = samples(values, width: width)
        let scale = scale(values, ceiling: ceiling)
        return (0..<height).map { row in
            String(samples.map { sample in
                switch sample {
                case .padding: return " "
                case .missing: return row == height - 1 ? "·" : " "
                case .value(let value):
                    let units = min(1, value / scale) * Double(height) * 8
                    let aboveBaseline = units - Double(height - row - 1) * 8
                    let level = Int(max(0, min(8, aboveBaseline)).rounded(.up))
                    return vertical[level]
                }
            })
        }
    }

    public static func meter(_ fraction: Double?, width: Int) -> String {
        guard width > 0 else { return "" }
        guard let fraction, fraction.isFinite else { return String(repeating: "·", count: width) }
        let units = max(0, min(1, fraction)) * Double(width) * 8
        return String((0..<width).map { column in
            let remaining = units - Double(column) * 8
            return horizontal[Int(max(0, min(8, remaining)).rounded(.up))]
        })
    }

    private static func valid(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return value
    }

    private static func scale(_ values: [Double?], ceiling: Double?) -> Double {
        if let ceiling, ceiling.isFinite, ceiling > 0 { return ceiling }
        return max(values.compactMap(valid).max() ?? 0, Double.leastNormalMagnitude)
    }

    private static func samples(_ values: [Double?], width: Int) -> [Sample] {
        if values.count <= width {
            let padding = Array(repeating: Sample.padding, count: width - values.count)
            return padding + values.map { value in valid(value).map(Sample.value) ?? .missing }
        }
        return (0..<width).map { column in
            let start = column * values.count / width
            let end = (column + 1) * values.count / width
            var peak = 0.0
            for value in values[start..<end] {
                // A gap invalidates its bucket: maxima must not conceal absent measurements.
                guard let value = valid(value) else { return .missing }
                peak = max(peak, value)
            }
            return .value(peak)
        }
    }
}
