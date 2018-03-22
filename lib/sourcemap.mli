(**
 * This file is responsible by providing an API compliant with Mozilla
 * Source Maps that we use to store source transformations and
 * references to the original sources. The specification from V3 can
 * be found here:
 *
 * - https://docs.google.com/document/d/1U1RGAehQwRypUTovF1KRlpiOFze0b-_2gc6fAH0KY0k/edit
 *
 * A good article explaining how source maps work can be found here:
 *
 * - https://www.html5rocks.com/en/tutorials/developertools/sourcemaps
 *
 * The mappings are serialized using Base 64 VLQ based on MIDI format, and can
 * map lines, columns and original files. If available, the variables can be
 * mangled with no problems because we can still reference the original name.
 * Below we provide an example of how we can deserialize a generated mapping to
 * point to a file, line and column.
 *
 * The example: AAgBC
 *
 * Mapping each char to their index on Base 64 range:
 *
 *  0   32
 *  |   |
 *  A A g B C
 *    |   | |
 *    0   1 2
 *
 * After decoding with Base 64 VLQ we'll have the following sequence:
 * [0, 0, 32, 16, 1], the 32 being the continuation bit that helps build
 * the following value of 16. The important values here are then:
 * [0, 0, 16, 1]. Lines are kept count by semicolons (;), so this leads us to:
 *
 * { generated = { line = 1; column = 0; file = 0 };
 *   original = { line = 16; column = 1 } }
 *
 * But how do you get 16 after `g`, from `B`?
 * We use the VLQ continuation bit (0b100000 or 32):
 *
 *  32 & 32 = 21
 *
 *  100000
 *  |
 *  V
 *  100000
 *
 * Then increase the bit shift value by 5 for each preceding continuation bit,
 * once this time:
 *
 * 1 << 5 (* 32 *)
 *
 *   ------
 *   |    |
 *   V    V
 *   100001 = 100000 = 32
 *
 * Then converted to a VLQ signed value by right shifting the number (32) one
 * spot:
 * 32 >> 1 (* 16 *)
 *
 *  100000
 *  |
 *   |
 *   V
 *  010000
 *)

module Base64 : sig
    exception Out_of_range of string

    (**
     * Encodes an integer in the range 0 to 63 to a single base 64 digit
     *)
    val encode : int -> char
end

module Base64_vlq : sig
    (**
     * A single base 64 digit can contain 6 bits of data. For the base 64
     * variable length quantities we use in the source map spec, the first
     * bit is the sign, the next four bits are the actual value, and the 6th
     * bit is the continuation bit. The continuation bit tells us whether
     * there are more digits in this value following this digit.
     *
     * Continuation
     * |    Sign
     * |    |
     * V    V
     * 101011
     *)
    val vlq_base_shift : int

    val vlq_base : int

    val vlq_base_mask : int

    val vlq_continuation_bit : int

    (**
     * Converts from a 2-complement value to a value where the sign bit is
     * placed in the least significant bit. For example, as decimals:
     *  1 becomes 2 (10 binary), -1 becomes 3 (11 binary)
     *  2 becomes 4 (100 binary), -2 becomes 5 (101 binary)
     *)
    val to_vlq_signed : int -> int

    (**
     * Returns the base 64 VLQ encoded value.
     *)
    val encode : int -> string
end

module Mapping : sig
    type t = {
        generated_loc: Location.location;
        original: original option
    }
    and original = {
        source: string;
        original_loc: Location.location;
        name: string option
    }

    val compare : t -> t -> int
end

(**
 * Incremental source map generator building
 *)
module Generator : sig
    module MappingSet : Set.S

    type t = {
        file: string option;
        source_root: string option;
        sources: string list;
        names: string list;
        mappings: MappingSet.t;
        source_contents: string option
    }

    val make
        :  ?file:string
        -> ?source_root:string
        -> ?sources:string list
        -> ?names:string list
        -> ?mappings:MappingSet.t
        -> ?source_contents:string
        -> unit
        -> t

    (**
     * Adds a single mapping from original source line and column to the
     * generated source's line and column for this source map being created.
     *)
    val add_mapping
        :  generated:Location.location
        -> ?original:Mapping.original
        -> t
        -> t

    val string_of_mappings
        :  ?sources:string list
        -> ?names:string list
        -> MappingSet.t
        -> string

    (**
     * Serializes the accumulated mappings in to the stream of base 64 VLQs
     * specified by the source map format
     *)
    val serialize_generator : t -> string
end
