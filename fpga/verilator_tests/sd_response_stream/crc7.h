inline uint8_t crc7(uint8_t prev, bool bit)
{
    /*
        Расчет crc7 побитно
        prev - предыдущее значение (изначально равно 0).
        bit - новый бит добавленный в последовательность.
        возвращает новое crc7 значение вместе с этим битом.
    */

    uint8_t inv = (bit?1:0) ^ ((prev>>6)&1);

    return (((prev<<1)|inv)^(inv<<3))&0b1111111;
}

//40 байт из 48-ми битного слова
inline uint8_t crc7_of_command(uint64_t data)
{
    uint8_t crc7_data = 0;
    for(int i=47; i>7; i--)
        crc7_data = crc7(crc7_data, (data>>i)&1);

    return crc7_data;
}

/*
 * data38 - 38 бит полезных данных
*/
inline uint64_t make_sd_command(uint64_t data38, bool host_to_periphery)
{
    uint64_t out = 0;
    if(host_to_periphery)
        out |= (1ull<<46);

    out |= (data38<<8);
    out |= crc7_of_command(out)<<1;
    //Последний бит всегда 1
    out |= 1;

    return out;
}
