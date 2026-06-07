# ============================================================
# gen_ram_test.py
#
# Genera vectores de prueba para:
# dual_port_ram_buffer
# permutation_controller
#
# ============================================================

def bit_reverse(value, width):

    binary = format(value, f'0{width}b')

    reversed_binary = binary[::-1]

    return int(reversed_binary, 2)


def generate_test_vectors(N):

    width = (N - 1).bit_length()

    print("")
    print("======================================")
    print(f" TEST VECTORS N = {N}")
    print("======================================")

    # Datos originales
    real_data = list(range(N))
    imag_data = [x + 100 for x in range(N)]

    print("")
    print("ORIGINAL ORDER")
    print("------------------------------")

    for i in range(N):

        print(f"addr={i:4d} "
              f"real={real_data[i]:4d} "
              f"imag={imag_data[i]:4d}")

    print("")
    print("BIT-REVERSED ORDER")
    print("------------------------------")

    for i in range(N):

        br = bit_reverse(i, width)

        print(f"index={i:4d} "
              f"bitrev={br:4d} "
              f"real={real_data[br]:4d} "
              f"imag={imag_data[br]:4d}")


if __name__ == "__main__":

    generate_test_vectors(8)
    generate_test_vectors(16)