KipuBankV2 es una versión mejorada del smart contract, diseñada para manejar depósitos y retiros de ETH y tokens ERC20, con control de acceso, contabilidad interna y soporte para precios en USD mediante Chainlink.  

Mejoras realizadas:

- Control de Acceso:
  - `DEFAULT_ADMIN_ROLE`: asignado al deployer, puede actualizar la capacidad total del banco (`setBankCapUSD`).  
  - `PAUSER_ROLE`: pausar depósitos y retiros en caso de emergencia, usando `Pausable` de OpenZeppelin.  

- Soporte Multi-token:  
  - Depósitos y retiros diferenciados de ETH y tokens ERC20.  
  - Validaciones específicas de cada token, usando transferFrom y transfer.  
  - Balance de cada usuario gestionado por token.  

- Contabilidad Interna:  
  - Mapping anidado `usuario -> token -> balance`.  
  - `address(0)` para ETH nativo.  
  - Funciones `_deposit` y `_withdraw` unificadas para todos los tipos de tokens.  
  - También se guarda dinámicamente (con un costo asimilado) el total del banco en USD (`totalBankUSD`) para compararlo con (`bankCapUSD`).

- Chainlink Price Feeds:
  - Chainlink para convertir montos de tokens a USD y controlar el límite global del banco en USD (`bankCapUSD`).  
  - Funciones para obtener el valor en USD de un token y para calcular el valor total de los depósitos.  

- Conversión de Decimales:
  - Manejo de distintos decimales de los tokens para unificar la contabilidad en USD.  
  - Uso de `feed.decimals()` y estandarización a 18 decimales para cálculos internos.

Despliegue

1. Clonar o descargar el proyecto desde GitHub.  
2. Abrir el archivo `KipuBank.sol` en Remix IDE.  
3. Compilar el contrato seleccionando la versión de Solidity `0.8.30`.  
4. Desplegar el contrato desde Remix, especificando el `bankCapUSD` en el constructor:  
    constructor(uint256 _bankCapUSD)

Contrato deployado:
    https://sepolia.etherscan.io/address/0x7e6b2be66e9ce3f05f9c2abe0a9c72e1738ed924
