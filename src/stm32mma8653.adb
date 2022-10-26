
--
-- Mehdi 24/10/2022 --
--
--  Test de l'accéléromètre mma8653
--

with Last_Chance_Handler;
pragma Unreferenced (Last_Chance_Handler);
--  The "last chance handler" is the user-defined routine that is called when
--  an exception is propagated. We need it in the executable, therefore it
--  must be somewhere in the closure of the context clauses.

with STM32.Board;

with Ada.Real_Time; use Ada.Real_Time;

-- Accéléromètre
with MMA8653; use MMA8653;
--with ST7735R.RAM_Framebuffer; use ST7735R.RAM_Framebuffer;

-- écran Oled
with SSD1306_V2;
with Bitmapped_Drawing;
with BMP_Fonts;
with HAL.Bitmap;

with STM32.Device;
with STM32.Setup;

with Ravenscar_Time;

-- pour Compute_Angles
with Ada.Numerics; use Ada.Numerics;
with Ada.Numerics.Elementary_Functions; use  Ada.Numerics.Elementary_Functions;


------------------
-- Stm32mma8653 --
------------------
procedure Stm32mma8653 is


	--------------------
	-- Compute_Angles --
	--------------------
	-- Calcul des angles en fonction des accelerations
	-- cf https://www.hobbytronics.co.uk/accelerometer-info
	procedure Compute_Angles (Acc_X, Acc_Y, Acc_Z    : in Float;
									Angle_X, Angle_Y       : out Float) is

		X_Square, Y_Square, Z_Square : Float;
	begin
		X_Square := Acc_X * Acc_X;
		Y_Square := Acc_Y * Acc_Y;
		Z_Square := Acc_Z * Acc_Z;

		Angle_X := Arctan (Acc_X / Sqrt (Y_Square + Z_Square));
		Angle_Y := Arctan (Acc_Y / Sqrt (X_Square + Z_Square));

	end Compute_Angles;



	Period       : constant Ada.Real_Time.Time_Span := Ada.Real_Time.Milliseconds (100);
	Next_Release : Ada.Real_Time.Time := Ada.Real_Time.Clock;

	Oled      : SSD1306_V2.SSD1306_V2_Screen (Buffer_Size_In_Byte              => (128 * 64) / 8,
														 Width                            => 128,
														 Height                           => 64,
														 Port                             => STM32.Device.I2C_1'Access,
														 RST                              => STM32.Device.PA0'Access, -- reset de l'écran ; PA0 choix arbitraire car pas utilisé mais obligatoire
														 Time                             => Ravenscar_Time.Delays);

	Accelerometer : MMA8653_Accelerometer (Port => STM32.Device.I2C_1'Access);

	-- valeurs lues sur l'accelerometre
	Data          : MMA8653.All_Axes_Data;
	Angle_X, Angle_Y       : Float; -- angles déduit des valeurs de l'accelerometre avec Compute_Angles

	Degre                  : constant := 180.0 / 3.1415; -- pour la conversion de rd en degré


	-- Pour la conversion de float en string :
	-- le profil Ravenscar ne permet pas l'utilisation de Float_IO
	-- mais on peut utiliser 'Img sur un type fixed point
	-- cf https://github.com/AdaCore/Ada_Drivers_Library/issues/294
	--   possible avec le run time ravenscar-full-stm32f4 : for Runtime ("ada") use "ravenscar-full-stm32f4";
	type Fixed_Type_Affichage is delta 0.1 digits 10;
	Angle_X_Fixed, Angle_Y_Fixed : Fixed_Type_Affichage;


begin

	-- initialiser la led utilisateur verte
	STM32.Board.Initialize_LEDs;
	STM32.Board.Turn_On (STM32.Board.Green_LED);

	-- initialisation du port I2C 1 pour l'écran oled ssd1306 en i2c
	STM32.Setup.Setup_I2C_Master   (Port      => STM32.Device.I2C_1,
											SDA         => STM32.Device.PB7,
											SCL         => STM32.Device.PB6,
											SDA_AF      => STM32.Device.GPIO_AF_I2C1_4,
											SCL_AF      => STM32.Device.GPIO_AF_I2C1_4,
											Clock_Speed => 100_000); -- 100 KHz

	-- initialisation des écrans oled sh1106
	Oled.Initialize;
	Oled.Initialize_Layer;
	Oled.Turn_On;

	-- clear screen
	Oled.Hidden_Buffer.Set_Source (HAL.Bitmap.Black);
	Oled.Hidden_Buffer.Fill;

	-- initialisation du port I2C 1 pour l'accès au MMA8653 en i2c sur PB6 et PB7 comme Oled
	-- sur la carte stm32 perso, le MMA8653 est connecté sur I2C_1 (PB6 et PB7)
	STM32.Setup.Setup_I2C_Master  (Port        => STM32.Device.I2C_1,
										  SDA         => STM32.Device.PB7,
										  SCL         => STM32.Device.PB6,
										  SDA_AF      => STM32.Device.GPIO_AF_I2C1_4,
										  SCL_AF      => STM32.Device.GPIO_AF_I2C1_4,
										  Clock_Speed => 100_000); -- Le MPU9250 peut échanger à 400 KHz
	-- nb : on peut mettre 400_000 (400 KHz) et ça continue à fonctionner en 100 KHz (fréquence de l'oled)


	-- On teste si l'accéléromètre est opérationnel
	Bitmapped_Drawing.Draw_String (Oled.Hidden_Buffer.all,
										  Start      => (0, 0),
										  Msg        => (if Accelerometer.Check_Device_Id then "MMA8653 OK" else "MMA8653 KO"),
										  Font       => BMP_Fonts.Font8x8,
										  Foreground => HAL.Bitmap.White,
										  Background => HAL.Bitmap.Black);

	Oled.Update_Layer;

	-- configuration de l'accéléromètre
	Accelerometer.Configure (Dyna_Range        => Two_G,
								  Sleep_Oversampling  => Normal,
								  Active_Oversampling => Normal);

	STM32.Board.Turn_Off (STM32.Board.Green_LED);


	loop
		STM32.Board.Toggle (STM32.Board.Green_LED);


		-- effacer la zone des coordonnées avant un nouvel affichage
		Oled.Hidden_Buffer.Set_Source (HAL.Bitmap.Black);
		Oled.Hidden_Buffer.Fill_Rect (Area => (Position => (0, 30),
													  Width    => 128,
													  Height   => 30));

		-- lecture des valeurs de l'accelerometre et calcul des angles
		Data := Accelerometer.Read_Data;

		Compute_Angles (Acc_X   => Float (Data.X),
						Acc_Y   => Float (Data.Y),
						Acc_Z   => Float (Data.Z),
						Angle_X => Angle_X,
						Angle_Y => Angle_Y);

		-- conversion en degrés et en fixed point type pour l'affichage
		Angle_X_Fixed := Fixed_Type_Affichage (Angle_X * Degre);
		Angle_Y_Fixed := Fixed_Type_Affichage (Angle_Y * Degre);

		Bitmapped_Drawing.Draw_String (Buffer     => Oled.Hidden_Buffer.all,
											Start      => (0, 20),
											Msg        => "X" & Angle_X_Fixed'Image,
											Font       => BMP_Fonts.Font8x8,
											Foreground => HAL.Bitmap.White,
											Background => HAL.Bitmap.Black);

		Bitmapped_Drawing.Draw_String (Buffer     => Oled.Hidden_Buffer.all,
											Start      => (0, 30),
											Msg        => "Y" & Angle_Y_Fixed'Image,
											Font       => BMP_Fonts.Font8x8,
											Foreground => HAL.Bitmap.White,
											Background => HAL.Bitmap.Black);



		-- mise à jour de l'affichage
		Oled.Update_Layer;

		Next_Release := Next_Release + Period;
		delay until Next_Release;

	end loop;

end Stm32mma8653;
