# ============================================================
# bit_reverse_ref.py
#
# Genera índices bit-reversed para:
# N = 8
# N = 16
# N = 1024
#
# Sirve como referencia para validar Verilog.
# ============================================================

def bit_reverse(value, width):
    """
    Invierte los bits de 'value'
    usando 'width' bits.
    """

    binary = format(value, f'0{width}b')

    reversed_binary = binary[::-1]

    return int(reversed_binary, 2)


def print_table(N):

    width = (N - 1).bit_length()

    print("")
    print("======================================")
    print(f" BIT-REVERSE TABLE N = {N}")
    print("======================================")

    for i in range(N):

        br = bit_reverse(i, width)

        print(f"{i:4d} -> {br:4d} | "
              f"{format(i, f'0{width}b')} -> "
              f"{format(br, f'0{width}b')}")


if __name__ == "__main__":

    print_table(8)
    print_table(16)
    print_table(1024)