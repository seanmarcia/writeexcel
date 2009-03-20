#!/usr/bin/ruby -w

##############################################################################
#
# A simple formatting example using Spreadsheet::WriteExcel.
#
# This program demonstrates the diagonal border cell format.
#
# reverse('©'), May 2004, John McNamara, jmcnamara@cpan.org
#

require 'writeexcel'
include Spreadsheet

workbook  = WriteExcel.new('diag_border.xls')
worksheet = workbook.add_worksheet

format1   = workbook.add_format(:diag_type       => 1)
format2   = workbook.add_format(:diag_type       => 2)
format3   = workbook.add_format(:diag_type       => 3)
format4   = workbook.add_format(
                              :diag_type       => 3,
                              :diag_border     => 7,
                              :diag_color      => 'red'
            )

worksheet.write('B3',  'Text', format1)
worksheet.write('B6',  'Text', format2)
worksheet.write('B9',  'Text', format3)
worksheet.write('B12', 'Text', format4)

workbook.close