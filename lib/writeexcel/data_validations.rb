module Writeexcel

class Worksheet < BIFFWriter
  require 'writeexcel/helper'

  class DataValidations < Array
    #
    # the count of the DV records to follow.
    #
    # Note, this could be wrapped into store_dv() but we may require separate
    # handling of the object id at a later stage.
    #
    def count_dv_record   #:nodoc:
      return if empty?

      dval_record(-1, size)  # obj_id = -1
    end

    private

    #
    # Store the DV record which contains the number of and information common to
    # all DV structures.
    #    obj_id       # Object ID number.
    #    dv_count     # Count of DV structs to follow.
    #
    def dval_record(obj_id, dv_count)   #:nodoc:
      record      = 0x01B2       # Record identifier
      length      = 0x0012       # Bytes to follow

      flags       = 0x0004       # Option flags.
      x_coord     = 0x00000000   # X coord of input box.
      y_coord     = 0x00000000   # Y coord of input box.

      # Pack the record.
      header = [record, length].pack('vv')
      data   = [flags, x_coord, y_coord, obj_id, dv_count].pack('vVVVV')

      header + data
    end
  end

  class DataValidation
    def initialize(parser, param)
      @parser        = parser
      @cells         = param[:cells]
      @validate      = param[:validate]
      @criteria      = param[:criteria]
      @value         = param[:value]
      @maximum       = param[:maximum]
      @input_title   = param[:input_title]
      @input_message = param[:input_message]
      @error_title   = param[:error_title]
      @error_message = param[:error_message]
      @error_type    = param[:error_type]
      @ignore_blank  = param[:ignore_blank]
      @dropdown      = param[:dropdown]
      @show_input    = param[:show_input]
      @show_error    = param[:show_error]
    end

    #
    # Calclate the DV record that specifies the data validation criteria and options
    # for a range of cells..
    #    cells             # Aref of cells to which DV applies.
    #    validate          # Type of data validation.
    #    criteria          # Validation criteria.
    #    value             # Value/Source/Minimum formula.
    #    maximum           # Maximum formula.
    #    input_title       # Title of input message.
    #    input_message     # Text of input message.
    #    error_title       # Title of error message.
    #    error_message     # Text of input message.
    #    error_type        # Error dialog type.
    #    ignore_blank      # Ignore blank cells.
    #    dropdown          # Display dropdown with list.
    #    input_box         # Display input box.
    #    error_box         # Display error box.
    #
    def dv_record  # :nodoc:
      record          = 0x01BE       # Record identifier
      length          = 0x0000       # Bytes to follow

      flags           = 0x00000000   # DV option flags.

      ime_mode        = 0            # IME input mode for far east fonts.
      str_lookup      = 0            # See below.

      # Set the string lookup flag for 'list' validations with a string array.
      if @validate == 3 && @value.respond_to?(:to_ary)
        str_lookup = 1
      end

      # The dropdown flag is stored as a negated value.
      no_dropdown = @dropdown ? 0 : 1

      # Set the required flags.
      flags |= @validate
      flags |= @error_type   << 4
      flags |= str_lookup    << 7
      flags |= @ignore_blank << 8
      flags |= no_dropdown   << 9
      flags |= ime_mode      << 10
      flags |= @show_input   << 18
      flags |= @show_error   << 19
      flags |= @criteria     << 20

      # Pack the validation formulas.
      formula_1 = pack_dv_formula(@value)
      formula_2 = pack_dv_formula(@maximum)

      # Pack the input and error dialog strings.
      input_title   = pack_dv_string(@input_title,   32 )
      error_title   = pack_dv_string(@error_title,   32 )
      input_message = pack_dv_string(@input_message, 255)
      error_message = pack_dv_string(@error_message, 255)

      # Pack the DV cell data.
      dv_count = @cells.size
      dv_data  = [dv_count].pack('v')
      @cells.each do |range|
        dv_data += [range[0], range[2], range[1], range[3]].pack('vvvv')
      end

      # Pack the record.
      data   = [flags].pack('V')     +
        input_title                  +
        error_title                  +
        input_message                +
        error_message                +
        formula_1                    +
        formula_2                    +
        dv_data

      header = [record, data.bytesize].pack('vv')

      header + data
    end

    private

    #
    # Pack the strings used in the input and error dialog captions and messages.
    # Captions are limited to 32 characters. Messages are limited to 255 chars.
    #
    def pack_dv_string(string = nil, max_length = 0)   #:nodoc:
      str_length  = 0
      encoding    = 0

      # The default empty string is "\0".
      unless string && string != ''
        string =
          ruby_18 { "\0" } || ruby_19 { "\0".encode('BINARY') }
      end

      # Excel limits DV captions to 32 chars and messages to 255.
      if string.bytesize > max_length
        string = string[0 .. max_length-1]
      end

      str_length = string.bytesize

      ruby_19 { string = convert_to_ascii_if_ascii(string) }

      # Handle utf8 strings
      if is_utf8?(string)
        str_length = string.gsub(/[^\Wa-zA-Z_\d]/, ' ').bytesize   # jlength
        string = utf8_to_16le(string)
        encoding = 1
      end

      ruby_18 { [str_length, encoding].pack('vC') + string } ||
      ruby_19 { [str_length, encoding].pack('vC') + string.force_encoding('BINARY') }
    end

    #
    # Pack the formula used in the DV record. This is the same as an cell formula
    # with some additional header information. Note, DV formulas in Excel use
    # relative addressing (R1C1 and ptgXxxN) however we use the Formula.pm's
    # default absolute addressing (A1 and ptgXxx).
    #
    def pack_dv_formula(formula = nil)   #:nodoc:
      encoding    = 0
      length      = 0
      unused      = 0x0000
      tokens      = []

      # Return a default structure for unused formulas.
      return [0, unused].pack('vv') unless formula && formula != ''

      # Pack a list array ref as a null separated string.
      if formula.respond_to?(:to_ary)
        formula   = formula.join("\0")
        formula   = '"' + formula + '"'
      end

      # Strip the = sign at the beginning of the formula string
      formula = formula.to_s unless formula.respond_to?(:to_str)
      formula.sub!(/^=/, '')

      # In order to raise formula errors from the point of view of the calling
      # program we use an eval block and re-raise the error from here.
      #
      tokens = @parser.parse_formula(formula)   # ????

      #       if ($@) {
      #           $@ =~ s/\n$//;  # Strip the \n used in the Formula.pm die()
      #           croak $@;       # Re-raise the error
      #       }
      #       else {
      #           # TODO test for non valid ptgs such as Sheet2!A1
      #       }

      # Force 2d ranges to be a reference class.
      tokens.each do |t|
        t.sub!(/_range2d/, "_range2dR")
        t.sub!(/_name/, "_nameR")
      end

      # Parse the tokens into a formula string.
      formula = @parser.parse_tokens(tokens)

      [formula.length, unused].pack('vv') + formula
    end
  end
end

end