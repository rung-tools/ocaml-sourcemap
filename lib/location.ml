(* Represents a location coordinate for a token *)
type location = {
    line: int;
    column: int
}
[@@deriving eq, show, ord]

(* The start and final locations for a token/lex buffer *)
type position = {
    start: location;
    end_: location
}
[@@deriving eq, show]
