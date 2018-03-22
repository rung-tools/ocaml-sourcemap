module Base64 = struct
    exception Out_of_range of string

    let encode number =
        let map = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/" in
        match number >= 0 && number < 64 with
        | true  -> map.[number]
        | false -> raise @@ Out_of_range "Must be between 0 and 63"
end

module Base64_vlq = struct
    let vlq_base_shift = 5

    (* binary: 100000 *)
    let vlq_base = 1 lsl vlq_base_shift

    (* binary: 011111 *)
    let vlq_base_mask = vlq_base - 1

    (* binary: 100000 *)
    let vlq_continuation_bit = vlq_base

    let to_vlq_signed value =
        match value < 0 with
        | true  -> ((-value) lsl 1) + 1
        | false -> value lsl 1

    let encode value =
        let vlq = to_vlq_signed value in
        let rec loop vlq encoded =
            let digit = vlq land vlq_base_mask in
            let shifted_vlq = vlq lsr vlq_base_shift in
            let digit_with_sign =
                match shifted_vlq > 0 with
                | true  ->
                    (* There are still more digits in this value, so we must
                       make sure the continuation digit is marked. *)
                    digit lor vlq_continuation_bit
                | false -> digit in
            let result = encoded ^ Char.escaped (Base64.encode digit_with_sign) in
            match shifted_vlq > 0 with
            | true  -> loop shifted_vlq result
            | false -> result
        in loop vlq ""
end

module Mapping = struct
    type t = {
        generated_loc: Location.location;
        original: original option
    }
    [@@deriving show, eq, ord]

    and original = {
        source: string;
        original_loc: Location.location;
        name: string option
    }
    [@@deriving show, eq, ord]
end

module Generator = struct
    module MappingSet = Set.Make(Mapping)

    type t = {
        file: string option;
        source_root: string option;
        sources: string list [@default []];
        names: string list [@default []];
        mappings: MappingSet.t [@default MappingSet.empty];
        source_contents: string option;
    }
    [@@deriving make]

    let add_mapping ~generated ?original generator =
        let mapping = { Mapping.generated_loc = generated; original } in
        match original with
        | None -> { generator with
            mappings = MappingSet.add mapping generator.mappings }
        | Some { Mapping.source; name; _ } -> { generator with
            mappings = MappingSet.add mapping generator.mappings;
            sources = generator.sources @ [source];
            names = generator.names @ Core.Option.value_map name ~default:[] ~f:Core.List.return }

    type state = {
        previous_generated: Location.location [@default { Location.line = 1; column = 0 }];
        previous_original: Location.location [@default { Location.line = 0; column = 0 }];
        previous_name_index: int [@default 0];
        previous_source_index: int [@default 0];
        first: bool [@default true]
    }
    [@@deriving make]

    let string_of_mappings ?(sources=[]) ?(names=[]) mappings =
        let find_index needle haystack = Core.List.find_mapi_exn haystack ~f:(fun index item ->
            match item = needle with
            | true  -> Some index
            | false -> None) in
        let sources = Core.List.dedup_and_sort sources in
        let names = Core.List.dedup_and_sort names in
        let buffer = Buffer.create 256 in
        let reducer (mapping : Mapping.t) state =
            let line_serializer generated_line state =
                match generated_line = state.previous_generated.line with
                | true ->
                    begin
                        match state.first with
                        | true  -> ()
                        | false -> Buffer.add_char buffer ','
                    end;
                    { state with first = false }
                | false ->
                     Buffer.add_string buffer (String.make (generated_line - state.previous_generated.line) ';');
                     { state with
                        previous_generated = { line = generated_line; column = 0 };
                        first = false } in
            let column_serializer generated_column state =
                let chunk = Base64_vlq.encode (generated_column - state.previous_generated.column) in
                Buffer.add_string buffer chunk;
                { state with
                    previous_generated = { state.previous_generated with column = generated_column } } in
            let original_serializer (original : Mapping.original option) state =
                match original with
                | Some { source; original_loc = { line; column }; name } ->
                    let source_index = find_index source sources in
                    let codes = List.map Base64_vlq.encode [
                        source_index - state.previous_source_index;
                        line - 1 - state.previous_original.line;
                        column - state.previous_original.column
                    ] in
                    Buffer.add_string buffer (String.concat "" codes);
                    let current_state = { state with
                        previous_original = { line = line - 1; column };
                        previous_source_index = source_index } in
                    begin match name with
                    | Some name ->
                        let name_index = find_index name names in
                        Buffer.add_string buffer (Base64_vlq.encode (name_index - state.previous_name_index));
                        { current_state with previous_name_index = name_index }
                    | None -> current_state
                    end
                | None -> state in
            state
            |> line_serializer mapping.generated_loc.line
            |> column_serializer mapping.generated_loc.column
            |> original_serializer mapping.original
        in ignore @@ MappingSet.fold reducer mappings (make_state ());
        Buffer.contents buffer

    let serialize_generator (generator : t) =
        string_of_mappings
            ~sources:generator.sources
            ~names:generator.names
            generator.mappings
end
